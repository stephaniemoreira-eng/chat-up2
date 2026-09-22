require 'rails_helper'

RSpec.describe OperationalEngine::Dispatcher do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:agent_tenant) do
    create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox, prospecting_agent_id: 77)
  end
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

  it 'pula a conta quando o agent_tenant nao esta configurado (sem whatsapp_inbox/prospecting_agent_id)' do
    agent_tenant.update!(whatsapp_inbox: nil)
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

  it 'a conversa ja existir conta como reivindicada mesmo se a chamada ao up2-agents falhar (nao tenta nao-atomicamente de novo no mesmo tick)' do
    stub_originate(status: 500, body: { error: 'boom' })
    build_lead(telefone: '+5513991234567')

    described_class.call(conta_id: account.id)

    expect(Conversation.where(account_id: account.id).count).to eq(1)
  end
end
