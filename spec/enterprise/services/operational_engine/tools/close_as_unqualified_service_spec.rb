require 'rails_helper'

RSpec.describe OperationalEngine::Tools::CloseAsUnqualifiedService do
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

  it 'encerra o lead como não qualificado, incluindo qualificacao_status' do
    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.lead_status).to eq('encerrado')
    expect(lead.motivo_encerramento).to eq('nao_qualificado')
    expect(lead.qualificacao_status).to eq('nao_qualificado')
  end

  it 'recusa quando já existe um agendamento confirmado' do
    lead.update!(agendamento_status: 'confirmado')

    expect(perform).to eq(ok: false, reason: 'lead tem um agendamento confirmado')
    expect(lead.reload.lead_status).to eq('ativo')
  end

  it 'é idempotente -- não duplica o evento' do
    perform
    perform

    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'encerrado_nao_qualificado').count).to eq(1)
  end
end
