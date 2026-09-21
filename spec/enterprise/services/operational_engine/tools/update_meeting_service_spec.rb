require 'rails_helper'

RSpec.describe OperationalEngine::Tools::UpdateMeetingService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:agent_tenant) do
    create(:up_sales_agent_tenant, account: account, calendar_integration_instance_id: 'instance-1')
  end
  let!(:lead) do
    OperationalEngine::Lead.create!(
      conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
      agendamento_status: 'confirmado', etapa_prospect: 'agendado', calendar_event_id: 'evt_123'
    )
  end

  def perform(**overrides)
    described_class.new(
      account: account, conversation_id: conversation.id, event_id: 'evt_123',
      starts_at: '2026-09-23T15:00:00-03:00', ends_at: '2026-09-23T15:30:00-03:00',
      **overrides
    ).call
  end

  def stub_update_event(status: 200, body: { event: { 'id' => 'evt_123', 'summary' => 'Reunião (remarcada)' } })
    stub_request(:patch, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events/evt_123')
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'retorna erro quando o lead não tem esse event_id como reunião confirmada' do
    lead.update!(calendar_event_id: 'outro_evento')

    result = perform

    expect(result).to eq(ok: false, reason: 'este lead não tem uma reunião confirmada com esse event_id')
    expect(a_request(:patch, /calendar\/events/)).not_to have_been_made
  end

  it 'retorna erro quando a reunião não está confirmada (mesmo com o event_id certo)' do
    lead.update!(agendamento_status: 'em_andamento')

    result = perform

    expect(result).to eq(ok: false, reason: 'este lead não tem uma reunião confirmada com esse event_id')
  end

  it 'retorna erro quando a conta não tem calendário conectado' do
    agent_tenant.update!(calendar_integration_instance_id: nil)

    result = perform

    expect(result).to eq(ok: false, reason: 'agenda não conectada para esta conta')
  end

  it 'reagenda o evento real e grava o evento de timeline' do
    stub_update_event

    result = perform

    expect(result).to eq(ok: true, event_id: 'evt_123')
    event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'reuniao_reagendada')
    expect(event).to be_present
    expect(event.metadata['calendar_event_id']).to eq('evt_123')
  end

  it 'não muda agendamento_status/etapa_prospect -- a reunião continua confirmada, só mudou de horário' do
    stub_update_event

    perform

    lead.reload
    expect(lead.agendamento_status).to eq('confirmado')
    expect(lead.etapa_prospect).to eq('agendado')
  end

  it 'não confirma nada quando o Calendar falha' do
    stub_update_event(status: 422, body: { error: 'Horário indisponível' })

    result = perform

    expect(result).to eq(ok: false, reason: 'Horário indisponível')
  end
end
