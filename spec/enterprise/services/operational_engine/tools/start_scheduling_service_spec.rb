require 'rails_helper'

RSpec.describe OperationalEngine::Tools::StartSchedulingService do
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

  it 'recusa um lead em não-contatar' do
    lead.update!(nao_contatar: true)

    expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
  end

  it 'marca o agendamento como em_andamento' do
    result = perform

    expect(result).to eq(ok: true)
    expect(lead.reload.agendamento_status).to eq('em_andamento')
  end

  it 'é idempotente -- chamar de novo já em_andamento não duplica o evento' do
    perform
    perform

    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'agendamento_iniciado').count).to eq(1)
  end

  %w[confirmado callback_registrado callback_realizado].each do |estado_ativo|
    it "recusa quando já existe um compromisso ativo (#{estado_ativo})" do
      lead.update!(agendamento_status: estado_ativo)

      expect(perform).to eq(ok: false, reason: 'já existe um compromisso ativo para este lead')
      expect(lead.reload.agendamento_status).to eq(estado_ativo)
    end
  end

  it 'permite reiniciar a partir de cancelado' do
    lead.update!(agendamento_status: 'cancelado')

    expect(perform).to eq(ok: true)
    expect(lead.reload.agendamento_status).to eq('em_andamento')
  end
end
