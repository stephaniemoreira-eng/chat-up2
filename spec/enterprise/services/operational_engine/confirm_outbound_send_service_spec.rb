require 'rails_helper'

RSpec.describe OperationalEngine::ConfirmOutboundSendService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def perform(message)
    described_class.call(message: message)
  end

  context 'lead nasceu no Backlog (outbound, §10.5)' do
    let!(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog')
    end

    it 'confirma o primeiro contato e move pra contatado' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)

      lead.reload
      expect(lead.primeiro_contato_em).to be_present
      expect(lead.etapa_prospect).to eq('contatado')
      expect(lead.etapa_entrou_em).to be_present
    end

    it 'grava o evento primeiro_contato_enviado' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)

      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'primeiro_contato_enviado')
      expect(event).to be_present
      expect(event.metadata['source_id']).to eq('wamid.abc')
    end

    it 'é idempotente -- não regride etapa_prospect nem duplica evento numa segunda confirmação' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)
      lead.update!(etapa_prospect: 'em_conversa') # avançou depois -- confirmação repetida não pode voltar
      perform(message)

      expect(lead.reload.etapa_prospect).to eq('em_conversa')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'primeiro_contato_enviado').count).to eq(1)
    end
  end

  context 'lead nasceu inbound (já em em_conversa, nunca passou por backlog)' do
    let!(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa')
    end

    it 'confirma o primeiro contato sem mexer em etapa_prospect' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)

      lead.reload
      expect(lead.primeiro_contato_em).to be_present
      expect(lead.etapa_prospect).to eq('em_conversa')
    end
  end

  it 'não faz nada quando não existe lead pra este telefone' do
    outro_contact = create(:contact, account: account, phone_number: '+5513999999999')
    outra_conversa = create(:conversation, account: account, contact: outro_contact)
    message = create(:message, conversation: outra_conversa, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

    expect { perform(message) }.not_to raise_error
  end

  it 'não faz nada quando o contato não tem telefone' do
    sem_telefone = create(:contact, account: account, phone_number: nil)
    conversa_sem_telefone = create(:conversation, account: account, contact: sem_telefone)
    message = create(:message, conversation: conversa_sem_telefone, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

    expect { perform(message) }.not_to raise_error
  end
end
