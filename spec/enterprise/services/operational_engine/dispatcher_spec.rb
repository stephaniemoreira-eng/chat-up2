require 'rails_helper'

RSpec.describe OperationalEngine::Dispatcher do
  let(:account) { create(:account) }
  # Precisa ser um inbox WhatsApp de verdade: ContactInboxBuilder só deriva um source_id
  # deterministico (por telefone) pro channel_type Channel::Whatsapp -- um inbox generico
  # (Channel::WebWidget, o default da factory :inbox) cai no branch SecureRandom.uuid, o que
  # quebraria a idempotencia que claim_conversation depende (first_or_create! por source_id).
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let!(:agent_tenant) do
    create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
  end
  # O id do agente de prospecção vem do slot "sdr" (UpSales::AgentSlot), não de uma coluna
  # própria em AgentTenant -- ver o comentário no modelo pra o porquê.
  let!(:sdr_slot) { create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '77') }
  # Terca, 10:00 America/Sao_Paulo -- dentro da janela da manha do BacklogCapacity.
  let(:business_hours) { Time.find_zone('America/Sao_Paulo').local(2026, 9, 22, 10, 0, 0) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}",
      etapa_prospect: 'backlog', etapa_entrou_em: 1.hour.ago
    }.merge(overrides))
  end

  def stub_originate(status: 200, body: { ok: true, outcome: 'posted' })
    stub_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  around do |example|
    travel_to(business_hours) { example.run }
  end

  it 'origina o primeiro contato pro proximo lead elegivel do Backlog' do
    stub_originate
    lead = build_lead(telefone: '+5513991234567', empresa: 'Lava e Pronto')

    described_class.call(conta_id: account.id)

    contact = Contact.find_by(phone_number: '+5513991234567')
    expect(contact).to be_present
    expect(contact.name).to eq('Lava e Pronto')

    conversation = Conversation.find_by(account_id: account.id, inbox_id: inbox.id)
    expect(conversation).to be_present
    expect(conversation.messages).to be_empty # quem manda a mensagem e o up2-agents, nao este service

    expect(
      a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')
        .with(body: hash_including('chatwootConversationId' => conversation.display_id))
    ).to have_been_made.once

    # invariante central (§10.6): originar NAO e ativar -- so ConfirmOutboundSendService grava isso.
    expect(lead.reload.primeiro_contato_em).to be_nil
    expect(lead.etapa_prospect).to eq('backlog')
  end

  it 'nao origina de novo quando ja existe uma conversa pro contact_inbox (idempotente)' do
    stub_originate
    build_lead(telefone: '+5513991234567')

    described_class.call(conta_id: account.id)
    described_class.call(conta_id: account.id)

    expect(
      a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')
    ).to have_been_made.once
  end

  it 'pula a conta quando o agent_tenant nao esta configurado (sem whatsapp_inbox)' do
    agent_tenant.update!(whatsapp_inbox: nil)
    stub_originate
    build_lead

    described_class.call(conta_id: account.id)

    expect(a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')).not_to have_been_made
  end

  it 'pula a conta quando nao ha slot sdr configurado (sem agente de prospeccao no up2-agents)' do
    sdr_slot.destroy!
    stub_originate
    build_lead

    described_class.call(conta_id: account.id)

    expect(a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')).not_to have_been_made
  end

  it 'pula um lead com nao_contatar=true' do
    stub_originate
    build_lead(nao_contatar: true)

    described_class.call(conta_id: account.id)

    expect(a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')).not_to have_been_made
  end

  it 'registra um LeadEvent quando a origination falha, sem propagar o erro' do
    stub_originate(status: 500, body: { error: 'up2-agents fora do ar' })
    lead = build_lead

    expect { described_class.call(conta_id: account.id) }.not_to raise_error

    event = lead.events.find_by(event_type: 'primeiro_contato_falhou')
    expect(event).to be_present
    expect(event.metadata['motivo']).to eq('up2-agents fora do ar')
  end

  describe 'autorizacao final antes do post (CP-01, P0-024-01/P0-022-02)' do
    let(:agent_bot) { create(:agent_bot) }
    let(:json) { { 'Content-Type' => 'application/json' } }

    # Simula o up2-agents: durante a "geracao" um fato novo pode entrar; depois ele tenta gravar a
    # abertura pelo mesmo caminho do post real (OutboundSendGate).
    def stub_originate_posting(before_post: nil)
      stub_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate').to_return do
        before_post&.call
        conversation = Conversation.find_by!(account_id: account.id, inbox_id: inbox.id)
        OperationalEngine::OutboundSendGate.authorize!(conversation: conversation) do
          create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                           sender: agent_bot, content: 'Oi, aqui e a Lavinia!')
        end
        { status: 200, body: { ok: true, outcome: 'posted' }.to_json, headers: json }
      rescue OperationalEngine::OutboundSendGate::Blocked => e
        { status: 200, body: { ok: false, outcome: 'blocked', reason: e.reason }.to_json, headers: json }
      end
    end

    def outgoing_messages
      Message.where(account_id: account.id, message_type: 'outgoing')
    end

    it 'grava a autorizacao da ativacao na conversa reivindicada' do
      stub_originate
      lead = build_lead(telefone: '+5513991234567')

      described_class.call(conta_id: account.id)

      activation = OperationalEngine::OriginationActivation.for(Conversation.find_by!(account_id: account.id))
      expect(activation.status).to eq('authorized')
      expect(activation.lead_id).to eq(lead.lead_id)
      expect(activation.activation_id).to be_present
      # CP-03 (P1-022-02): a mesma identidade vai para o up2-agents (Snapshot primeiro_contato + turn_id).
      expect(
        a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')
          .with(body: hash_including('activationId' => activation.activation_id))
      ).to have_been_made.once
    end

    it 'lead elegivel: a abertura sai e consome a ativacao' do
      build_lead(telefone: '+5513991234567')
      stub_originate_posting

      described_class.call(conta_id: account.id)

      expect(outgoing_messages.count).to eq(1)
      expect(OperationalEngine::OriginationActivation.for(Conversation.find_by!(account_id: account.id)).status).to eq('consumed')
    end

    it 'opt-out entra enquanto a abertura e gerada: nenhuma mensagem sai' do
      lead = build_lead(telefone: '+5513991234567')
      stub_originate_posting(before_post: -> { OperationalEngine::Lead.find(lead.lead_id).update!(nao_contatar: true) })

      described_class.call(conta_id: account.id)

      expect(outgoing_messages).to be_empty
    end

    it 'humano assume enquanto a abertura e gerada: nenhuma mensagem automatica sai' do
      lead = build_lead(telefone: '+5513991234567')
      user = create(:user, account: account)
      stub_originate_posting(before_post: lambda {
        OperationalEngine::TakeoverService.assumir!(lead: OperationalEngine::Lead.find(lead.lead_id), user_id: user.id)
      })

      described_class.call(conta_id: account.id)

      expect(outgoing_messages).to be_empty
    end

    it 'lead vira cliente atual / e encerrado enquanto a abertura e gerada: nenhuma mensagem sai' do
      lead = build_lead(telefone: '+5513991234567')
      stub_originate_posting(before_post: lambda {
        OperationalEngine::Lead.find(lead.lead_id).update!(relacao_atual: 'cliente_atual', lead_status: 'encerrado',
                                                           motivo_encerramento: 'cliente_atual')
      })

      described_class.call(conta_id: account.id)

      expect(outgoing_messages).to be_empty
    end
  end

  it 'a conversa ja existir conta como reivindicada mesmo se a chamada ao up2-agents falhar (nao tenta nao-atomicamente de novo no mesmo tick)' do
    stub_originate(status: 500, body: { error: 'boom' })
    build_lead(telefone: '+5513991234567')

    described_class.call(conta_id: account.id)

    expect(Conversation.where(account_id: account.id).count).to eq(1)
  end
end
