require 'rails_helper'

RSpec.describe OperationalEngine::Tools::CancelMeetingService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:agent_tenant) do
    create(:up_sales_agent_tenant, account: account, calendar_integration_instance_id: 'instance-1')
  end
  let!(:lead) do
    OperationalEngine::Lead.create!(
      conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
      agendamento_status: 'confirmado', etapa_prospect: 'agendado', calendar_event_id: 'evt_123',
      agendado_em: Time.current
    )
  end

  def perform(**overrides)
    described_class.new(account: account, conversation_id: conversation.display_id, event_id: 'evt_123', **overrides).call
  end

  def stub_cancel_event(status: 200)
    stub_request(:delete, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events/evt_123')
      .to_return(status: status, body: { instance: {}, ok: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'retorna erro quando o lead não tem esse event_id como reunião confirmada' do
    lead.update!(calendar_event_id: 'outro_evento')

    result = perform

    expect(result).to eq(ok: false, reason: 'este lead não tem uma reunião confirmada com esse event_id')
    expect(a_request(:delete, /calendar\/events/)).not_to have_been_made
  end

  it 'retorna erro quando a conta não tem calendário conectado' do
    agent_tenant.update!(calendar_integration_instance_id: nil)

    result = perform

    expect(result).to eq(ok: false, reason: 'agenda não conectada para esta conta')
  end

  # CP-04 (P1-023-01/P2-023-01, SSOT §28.29): cancelar não regride Agendado→Qualificado.
  it 'cancela a reunião: agendamento_status=cancelado, etapa Prospect continua Agendado' do
    stub_cancel_event

    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.agendamento_status).to eq('cancelado')
    expect(lead.etapa_prospect).to eq('agendado')
  end

  it 'não mexe em conversao_em/tipo_conversao/calendar_event_id/agendado_em' do
    lead.update!(conversao_em: 1.day.ago.change(usec: 0), tipo_conversao: 'agendamento')
    stub_cancel_event

    perform

    lead.reload
    expect(lead.conversao_em).to be_present
    expect(lead.tipo_conversao).to eq('agendamento')
    expect(lead.calendar_event_id).to eq('evt_123')
    expect(lead.agendado_em).to be_present
  end

  it 'grava o evento reuniao_cancelada' do
    stub_cancel_event

    perform

    event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'reuniao_cancelada')
    expect(event).to be_present
    expect(event.metadata['calendar_event_id']).to eq('evt_123')
  end

  it 'o card do Kanban Prospect continua em Agendado (projeção segue o Engine)' do
    stub_cancel_event

    perform

    sales_lead = Sales::Lead.find_by(contact_id: contact.id)
    expect(sales_lead.stage.engine_stage_key).to eq('agendado')
  end

  it 'não muda nada quando o Calendar falha' do
    stub_request(:delete, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events/evt_123')
      .to_return(status: 500, body: { error: 'Falha no Google' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = perform

    expect(result).to eq(ok: false, reason: 'Falha no Google')
    expect(lead.reload.agendamento_status).to eq('confirmado')
  end

  # CP-10 (P1-VAL-03): ferramenta "Cancelar evento" da Lavínia -- o modelo não carrega event_id.
  describe 'modo agent (CP-10)' do
    it 'sem event_id, cancela a reunião confirmada do próprio lead sem regredir a etapa (28.29)' do
      stub_cancel_event

      expect(perform(event_id: nil)).to eq(ok: true)
      lead.reload
      expect(lead.agendamento_status).to eq('cancelado')
      expect(lead.etapa_prospect).to eq('agendado')
    end

    it 'lead em atendimento humano: recusa sem tocar o Calendar' do
      lead.update!(modo_atendimento: 'humano')

      expect(perform(event_id: nil)).to eq(ok: false, reason: 'lead em atendimento humano')
      expect(a_request(:delete, %r{calendar/events})).not_to have_been_made
      expect(lead.reload.agendamento_status).to eq('confirmado')
    end

    it 'falha do Calendar: reunião continua confirmada' do
      stub_cancel_event(status: 500)

      result = perform(event_id: nil)

      expect(result[:ok]).to be(false)
      expect(lead.reload.agendamento_status).to eq('confirmado')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'reuniao_cancelada')).to be_empty
    end
  end
end
