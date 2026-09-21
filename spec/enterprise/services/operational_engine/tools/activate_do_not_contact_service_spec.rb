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
end
