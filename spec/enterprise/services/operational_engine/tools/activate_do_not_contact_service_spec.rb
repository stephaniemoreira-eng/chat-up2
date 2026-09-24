require 'rails_helper'

RSpec.describe OperationalEngine::Tools::ActivateDoNotContactService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id)
  end

  def perform
    described_class.new(account: account, conversation_id: conversation.id).call
  end

  it 'retorna erro quando a conversa não existe' do
    result = described_class.new(account: account, conversation_id: -1).call

    expect(result).to eq(ok: false, reason: 'conversa não encontrada')
  end

  it 'ativa não-contatar e encerra o lead' do
    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.nao_contatar).to eq(true)
    expect(lead.lead_status).to eq('encerrado')
    expect(lead.motivo_encerramento).to eq('nao_contatar')
  end

  it 'vale mesmo com um agendamento confirmado -- não tem guarda de estado' do
    lead.update!(agendamento_status: 'confirmado')

    expect(perform).to eq(ok: true)
    expect(lead.reload.nao_contatar).to eq(true)
  end

  it 'é idempotente -- não duplica o evento' do
    perform
    perform

    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'nao_contatar_ativado').count).to eq(1)
  end

  # CP-01 -- P0-018-01 (§19.2, §28.25, §28.26).
  describe 'cancelamento da automação pendente' do
    it 'encerra recovery, limpa a próxima recovery e para de aguardar resposta' do
      lead.update!(recuperacao_status: 'ativa', proxima_recuperacao_em: 1.day.from_now, aguardando_resposta: true)

      perform

      lead.reload
      expect(lead.recuperacao_status).to eq('inativa')
      expect(lead.proxima_recuperacao_em).to be_nil
      expect(lead.aguardando_resposta).to be(false)
    end

    it 'vale mesmo com humano na conversa -- opt-out prevalece' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: create(:user, account: account).id)

      expect(perform).to eq(ok: true)
      expect(lead.reload.nao_contatar).to be(true)
    end

    it 'invalida de forma verificável a abertura outbound ainda pendente do contato' do
      pending_conversation = create(:conversation, account: account, contact: contact,
                                                   additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))

      perform

      activation = OperationalEngine::OriginationActivation.for(pending_conversation.reload)
      expect(activation.status).to eq('cancelled')
      expect(pending_conversation.additional_attributes.dig('up_sales_origination', 'motivo')).to eq('nao_contatar')
    end

    it 'replay com a flag já ativa ainda garante a automação desligada, sem evento novo' do
      perform
      lead.reload.update!(recuperacao_status: 'ativa', proxima_recuperacao_em: 1.day.from_now)

      perform

      expect(lead.reload.recuperacao_status).to eq('inativa')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'nao_contatar_ativado').count).to eq(1)
    end

    it 'inbound posterior do contato não limpa a flag (§28.26)' do
      perform
      message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                                 message_type: 'incoming', sender: contact)

      OperationalEngine::InboundProcessor.call(message: message)

      lead.reload
      expect(lead.nao_contatar).to be(true)
      expect(lead.lead_status).to eq('encerrado')
    end

    it 'automação já preparada não consegue enviar depois do opt-out; resposta ao inbound novo consegue' do
      create(:up_sales_agent_tenant, account: account)
      agent_bot = create(:agent_bot)
      perform
      post_bot = lambda do
        OperationalEngine::OutboundSendGate.authorize!(conversation: conversation) do
          create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                           message_type: 'outgoing', sender: agent_bot, content: 'Oi de novo!')
        end
      end

      expect { post_bot.call }.to raise_error(OperationalEngine::OutboundSendGate::Blocked)

      create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                       message_type: 'incoming', sender: contact)
      expect(post_bot.call).to be_persisted
    end
  end
end
