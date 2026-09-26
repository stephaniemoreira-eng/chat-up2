require 'rails_helper'

# CP-02 -- P0-019-01: a rede de segurança recupera confirmações perdidas a partir de estado durável.
RSpec.describe OperationalEngine::OutboundConfirmationReconciler do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, modo_entrada: 'outbound', etapa_prospect: 'backlog')
  end
  let(:conversation) do
    create(:conversation, account: account, contact: contact,
                          additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
  end

  def consumed_opening(source_id:)
    message = create(:message, account: account, conversation: conversation, message_type: 'outgoing', source_id: source_id)
    OperationalEngine::OriginationActivation.for(conversation).transition!('consumed', message_id: message.id)
    message
  end

  it 'recupera a confirmação de uma abertura já confirmada pelo provider cujo lead ficou em Backlog' do
    consumed_opening(source_id: 'wamid.perdido')

    expect(described_class.call(account_id: account.id)).to eq(1)

    lead.reload
    expect(lead.etapa_prospect).to eq('contatado')
    expect(lead.entrada_operacao_em).to be_present
  end

  it 'não mexe em abertura ainda sem source_id (o provider não confirmou)' do
    consumed_opening(source_id: nil)

    expect(described_class.call(account_id: account.id)).to eq(0)
    expect(lead.reload.primeiro_contato_em).to be_nil
  end

  it 'é idempotente: nada a recuperar depois de confirmado' do
    consumed_opening(source_id: 'wamid.ok')
    described_class.call(account_id: account.id)

    expect(described_class.call(account_id: account.id)).to eq(0)
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'primeiro_contato_enviado').count).to eq(1)
  end
end
