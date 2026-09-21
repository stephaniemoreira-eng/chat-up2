require 'rails_helper'

describe OperationalEngineListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  # Sem telefone de propósito: os 3 testes genéricos abaixo (só log) não devem ter efeito
  # colateral no Operational Engine. Os describes de inbound/auto-assume abaixo criam seu
  # próprio contato com telefone, onde o efeito colateral é exatamente o que está sendo testado.
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, conversation: conversation, account: account) }

  it 'loga message_created' do
    event = Events::Base.new(:message_created, Time.zone.now, message: message)

    expect(Rails.logger).to receive(:info).with(/message_created.*"message_id":#{message.id}/)
    listener.message_created(event)
  end

  it 'loga message_updated com as chaves alteradas' do
    event = Events::Base.new(:message_updated, Time.zone.now, message: message, previous_changes: { 'status' => %w[sent delivered] })

    expect(Rails.logger).to receive(:info).with(/message_updated.*"status"/)
    listener.message_updated(event)
  end

  it 'loga assignee_changed' do
    event = Events::Base.new(:assignee_changed, Time.zone.now, conversation: conversation)

    expect(Rails.logger).to receive(:info).with(/assignee_changed.*"conversation_id":#{conversation.id}/)
    listener.assignee_changed(event)
  end

  describe 'inbound (Fase 3, §11)' do
    let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }

    it 'mensagem incoming aciona o InboundProcessor e cria o lead' do
      incoming = create(:message, conversation: conversation, account: account, message_type: 'incoming')
      event = Events::Base.new(:message_created, Time.zone.now, message: incoming)

      expect { listener.message_created(event) }.to change(OperationalEngine::Lead, :count).by(1)
    end
  end

  describe 'auto-assume (Fase 3, §18.2, testes 28.20/28.21)' do
    let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
    let!(:lead) do
      OperationalEngine::LeadRepository.find_or_create_by_telefone(conta_id: account.id, telefone: contact.phone_number)
    end
    let(:agent) { create(:user, account: account) }

    it 'mensagem publica humana assume a conversa (teste 28.20)' do
      reply = create(:message, conversation: conversation, account: account,
                                message_type: 'outgoing', sender: agent, private: false)
      event = Events::Base.new(:message_created, Time.zone.now, message: reply)

      listener.message_created(event)

      expect(lead.reload.modo_atendimento).to eq('humano')
      expect(lead.responsavel_atual_id).to eq(agent.id)
    end

    it 'nota privada nao assume (teste 28.21)' do
      note = create(:message, conversation: conversation, account: account,
                               message_type: 'outgoing', sender: agent, private: true)
      event = Events::Base.new(:message_created, Time.zone.now, message: note)

      listener.message_created(event)

      expect(lead.reload.modo_atendimento).to eq('lavinia')
    end

    it 'mensagem de bot/AgentBot nao assume' do
      bot_reply = create(:message, conversation: conversation, account: account,
                                    message_type: 'outgoing', sender: create(:agent_bot))
      event = Events::Base.new(:message_created, Time.zone.now, message: bot_reply)

      listener.message_created(event)

      expect(lead.reload.modo_atendimento).to eq('lavinia')
    end
  end

  describe 'confirmação de envio (Fase 6, §10.6, S-7)' do
    let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
    let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog') }

    it 'source_id saindo de nulo pra presente numa mensagem outgoing aciona a confirmação' do
      outgoing = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')
      event = Events::Base.new(:message_updated, Time.zone.now, message: outgoing, previous_changes: { 'source_id' => [nil, 'wamid.abc'] })

      listener.message_updated(event)

      expect(lead.reload.primeiro_contato_em).to be_present
    end

    it 'source_id já preenchido antes não é "acabou de confirmar" -- não aciona de novo' do
      outgoing = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')
      event = Events::Base.new(:message_updated, Time.zone.now, message: outgoing, previous_changes: { 'source_id' => %w[wamid.old wamid.abc] })

      listener.message_updated(event)

      expect(lead.reload.primeiro_contato_em).to be_nil
    end

    it 'mudança que não é source_id não aciona a confirmação' do
      outgoing = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')
      event = Events::Base.new(:message_updated, Time.zone.now, message: outgoing, previous_changes: { 'status' => %w[sent delivered] })

      listener.message_updated(event)

      expect(lead.reload.primeiro_contato_em).to be_nil
    end

    it 'mensagem incoming ganhando source_id não aciona -- confirmação é só pro nosso envio' do
      incoming = create(:message, conversation: conversation, account: account, message_type: 'incoming', source_id: 'wamid.abc')
      event = Events::Base.new(:message_updated, Time.zone.now, message: incoming, previous_changes: { 'source_id' => [nil, 'wamid.abc'] })

      listener.message_updated(event)

      expect(lead.reload.primeiro_contato_em).to be_nil
    end
  end

  it 'nao deixa uma falha do Engine derrubar o dispatch' do
    incoming = create(:message, conversation: conversation, account: account, message_type: 'incoming')
    event = Events::Base.new(:message_created, Time.zone.now, message: incoming)
    allow(OperationalEngine::InboundProcessor).to receive(:call).and_raise('boom')

    expect(ChatwootExceptionTracker).to receive(:new).and_call_original
    expect { listener.message_created(event) }.not_to raise_error
  end

  it 'nao deixa uma falha na confirmação de envio derrubar o dispatch' do
    contact_com_telefone = create(:contact, account: account, phone_number: '+5513991234567')
    conversa = create(:conversation, account: account, contact: contact_com_telefone)
    outgoing = create(:message, conversation: conversa, account: account, message_type: 'outgoing', source_id: 'wamid.abc')
    event = Events::Base.new(:message_updated, Time.zone.now, message: outgoing, previous_changes: { 'source_id' => [nil, 'wamid.abc'] })
    allow(OperationalEngine::ConfirmOutboundSendService).to receive(:call).and_raise('boom')

    expect(ChatwootExceptionTracker).to receive(:new).and_call_original
    expect { listener.message_updated(event) }.not_to raise_error
  end
end
