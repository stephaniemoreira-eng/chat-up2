require 'rails_helper'

# CP-01 -- P0-022-02, P0-024-01, P0-018-01 (lado envio), SSOT §12.4/§19/§23.2.
RSpec.describe OperationalEngine::OutboundSendGate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:agent_bot) { create(:agent_bot) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog',
                                    etapa_entrou_em: 1.hour.ago, upsales_contact_id: contact.id)
  end
  # Conversa como o Dispatcher a deixa depois do claim: ativação "authorized", ninguém falou ainda.
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                          additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
  end

  def post_bot_message(content: 'Oi, aqui é a Lavínia da Lava e Pronto!')
    described_class.authorize!(conversation: conversation) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                       sender: agent_bot, content: content)
    end
  end

  def incoming!(at: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming',
                     sender: contact, created_at: at)
  end

  def expect_blocked(reason_pattern)
    expect { post_bot_message }.to raise_error(described_class::Blocked) { |e| expect(e.reason).to match(reason_pattern) }
    expect(conversation.messages.outgoing.where(sender: agent_bot)).to be_empty
  end

  def activation
    OperationalEngine::OriginationActivation.for(conversation.reload)
  end

  describe '.applies?' do
    it 'só vale pra mensagem pública do AgentBot em conta com Operational Engine' do
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: {})).to be(true)
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: { message_type: 'template' })).to be(true)
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: { private: true })).to be(false)
      expect(described_class.applies?(conversation: conversation, sender: create(:user, account: account), params: {})).to be(false)

      agent_tenant.destroy!
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: {})).to be(false)
    end
  end

  describe 'abertura do Dispatcher (ativação authorized)' do
    it 'deixa sair quando o lead continua elegível e consome a ativação' do
      message = post_bot_message

      expect(message).to be_persisted
      expect(activation.status).to eq('consumed')
      expect(activation.conversation.additional_attributes.dig('up_sales_origination', 'message_id')).to eq(message.id)
    end

    it 'bloqueia quando nao_contatar entrou depois do claim' do
      lead.update!(nao_contatar: true)

      expect_blocked(/nao_contatar/)
      expect(activation.status).to eq('authorized')
    end

    it 'bloqueia quando um humano assumiu depois do claim' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: create(:user, account: account).id)

      expect_blocked(/atendimento_humano/)
    end

    it 'bloqueia quando o lead virou cliente atual' do
      lead.update!(relacao_atual: 'cliente_atual')

      expect_blocked(/cliente_atual/)
    end

    it 'bloqueia quando o lead foi encerrado' do
      lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')

      expect_blocked(/lead_encerrado/)
    end

    it 'bloqueia quando o lead saiu do Backlog (estado incompatível)' do
      lead.update!(etapa_prospect: 'em_conversa')

      expect_blocked(/fora_do_backlog/)
    end

    it 'bloqueia quando outra ativação já teve a primeira abordagem confirmada' do
      lead.update!(primeiro_contato_em: 1.minute.ago)

      expect_blocked(/primeira_abordagem_ja_enviada/)
    end

    it 'bloqueia quando outra conversa do mesmo contato já consumiu uma ativação (ativação concorrente)' do
      other = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                    additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
      OperationalEngine::OriginationActivation.for(other).transition!('consumed', message_id: 1)

      expect_blocked(/ativacao_concorrente/)
    end

    it 'fato novo gravado enquanto o gate esperava o lock vence a ação preparada' do
      # O gate carrega o lead (fotografia elegível); antes de ele tomar o lock, o opt-out é
      # persistido por outro processo. with_lock relê a linha -- o fato novo tem que vencer.
      allow(OperationalEngine::LeadRepository).to receive(:find_by_telefone).and_wrap_original do |original, **kwargs|
        stale = original.call(**kwargs)
        OperationalEngine::Lead.find(stale.lead_id).update!(nao_contatar: true)
        stale
      end

      expect_blocked(/nao_contatar/)
    end

    it 'sem ativação válida e sem mensagem do contato, lead em Backlog não recebe abertura' do
      activation.transition!('cancelled', motivo: 'nao_contatar')

      expect_blocked(/primeira_abordagem_sem_autorizacao/)
    end
  end

  describe 'resposta nova' do
    it 'o contato falar antes da abertura invalida a ativação; a mensagem vira conversa' do
      incoming!

      message = post_bot_message(content: 'Oi! Como posso ajudar?')

      expect(message).to be_persisted
      expect(activation.status).to eq('superseded')
    end
  end

  describe 'proteções contra contato proativo (§19.1, §19.2, §28.25, §28.26)' do
    before do
      lead.update!(etapa_prospect: 'em_conversa')
      activation.transition!('consumed', message_id: 1)
    end

    it 'nao_contatar + contato acabou de falar: responde o inbound sem limpar a flag' do
      lead.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar')
      incoming!(at: 1.minute.ago)

      expect(post_bot_message).to be_persisted
      expect(lead.reload.nao_contatar).to be(true)
    end

    it 'nao_contatar + nenhuma mensagem recente do contato: automação proativa (timer/nudge) bloqueada' do
      lead.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar')
      incoming!(at: 2.hours.ago)

      expect_blocked(/contato_proativo_bloqueado:.*nao_contatar/)
    end

    it 'cliente atual: contato proativo bloqueado' do
      lead.update!(relacao_atual: 'cliente_atual')
      incoming!(at: 3.days.ago)

      expect_blocked(/cliente_atual/)
    end

    it 'lead ativo em conversa: nada bloqueia' do
      incoming!(at: 3.hours.ago)

      expect(post_bot_message).to be_persisted
    end
  end

  describe 'atendimento humano (§18.2, §23.2)' do
    before do
      lead.update!(etapa_prospect: 'em_conversa')
      activation.transition!('consumed', message_id: 1)
      incoming!(at: 1.minute.ago)
    end

    it 'humano assumiu: resposta automática bloqueada mesmo com o contato tendo acabado de falar' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: create(:user, account: account).id)

      expect_blocked(/atendimento_humano/)
    end

    describe 'depois de handoff_comercial feito pela própria Lavínia' do
      before do
        OperationalEngine::Tools::HandoffToCommercialService.new(
          account: account, conversation_id: conversation.display_id, motivo_handoff: 'avanco_comercial'
        ).call
      end

      it 'deixa sair a resposta do turno do handoff dentro da janela' do
        expect(post_bot_message(content: 'Vou te passar para o comercial.')).to be_persisted
      end

      it 'bloqueia depois da janela técnica' do
        travel(described_class.handoff_reply_window + 1.second) { expect_blocked(/atendimento_humano/) }
      end

      it 'bloqueia quando um humano já reivindicou a conversa' do
        lead.reload.update!(responsavel_atual_id: create(:user, account: account).id)

        expect_blocked(/atendimento_humano/)
      end

      it 'bloqueia quando um humano já escreveu na conversa depois do handoff' do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                         sender: create(:user, account: account), content: 'Oi, aqui é o Danilo')

        expect_blocked(/atendimento_humano/)
      end
    end
  end

  it 'falha fechado quando o Engine não responde' do
    allow(OperationalEngine::LeadRepository).to receive(:find_by_telefone).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect_blocked(/engine_indisponivel/)
  end

  it 'contato com telefone e sem lead resolvido: falha fechado (RISK-019-02)' do
    contact.update!(phone_number: '+5511988887777')

    expect_blocked(/lead_nao_resolvido/)
  end

  it 'contato sem telefone (fora do Engine) segue o fluxo nativo' do
    contact.update!(phone_number: nil)

    expect(post_bot_message).to be_persisted
  end

  it 'a janela de resposta padrão é curta (5 min): lembrete/nudge logo depois não passa por "resposta"' do
    expect(described_class.reply_window).to eq(5.minutes)
  end
end
