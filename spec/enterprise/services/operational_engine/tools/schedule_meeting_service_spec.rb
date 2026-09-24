require 'rails_helper'

RSpec.describe OperationalEngine::Tools::ScheduleMeetingService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:agent_tenant) do
    create(:up_sales_agent_tenant, account: account, calendar_integration_instance_id: 'instance-1')
  end
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id)
  end

  def perform(**overrides)
    described_class.new(
      account: account,
      conversation_id: conversation.display_id,
      summary: 'Reunião com Lavínia',
      starts_at: '2026-09-22T14:00:00-03:00',
      ends_at: '2026-09-22T14:30:00-03:00',
      description: nil,
      **overrides
    ).call
  end

  def stub_create_event(status: 200, body: { event: { 'id' => 'evt_123', 'htmlLink' => 'https://calendar.google.com/evt_123' } })
    stub_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events')
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'retorna erro quando a conversa não existe' do
    result = perform(conversation_id: -1)

    expect(result).to eq(ok: false, reason: 'conversa não encontrada')
  end

  it 'retorna erro quando não existe lead pra essa conversa' do
    lead.destroy!

    result = perform

    expect(result).to eq(ok: false, reason: 'lead não encontrado para esta conversa')
  end

  it 'retorna erro quando a conta não tem calendário conectado' do
    agent_tenant.update!(calendar_integration_instance_id: nil)

    result = perform

    expect(result).to eq(ok: false, reason: 'agenda não conectada para esta conta')
  end

  it 'cria o evento real e confirma o agendamento (SSOT §16)' do
    stub_create_event

    result = perform

    expect(result).to eq(ok: true, event_id: 'evt_123')
    lead.reload
    expect(lead.calendar_event_id).to eq('evt_123')
    expect(lead.agendamento_status).to eq('confirmado')
    expect(lead.etapa_prospect).to eq('agendado')
    expect(lead.agendado_em).to be_present
    expect(lead.conversao_em).to eq(lead.agendado_em)
    expect(lead.tipo_conversao).to eq('agendamento')
  end

  it 'grava o evento reuniao_agendada' do
    stub_create_event

    perform

    event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'reuniao_agendada')
    expect(event).to be_present
    expect(event.source).to eq('lavinia')
    expect(event.metadata['calendar_event_id']).to eq('evt_123')
  end

  it 'sincroniza o card do Kanban Prospect pra agendado' do
    stub_create_event

    perform

    sales_lead = Sales::Lead.find_by(contact_id: contact.id)
    expect(sales_lead.stage.engine_stage_key).to eq('agendado')
  end

  it 'não confirma nem grava nada quando o Calendar falha (proibição explícita do Marco 1)' do
    stub_create_event(status: 422, body: { error: 'Calendário inválido' })

    result = perform

    expect(result).to eq(ok: false, reason: 'Calendário inválido')
    lead.reload
    expect(lead.agendamento_status).to eq('nao_iniciado')
    expect(lead.calendar_event_id).to be_nil
    expect(lead.conversao_em).to be_nil
  end

  it 'é idempotente: uma segunda chamada num lead já confirmado não cria outro evento' do
    lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_already', etapa_prospect: 'agendado', agendado_em: Time.current)

    result = perform

    expect(result).to eq(ok: true, event_id: 'evt_already')
    expect(a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events')).not_to have_been_made
  end

  it 'não reescreve conversao_em/tipo_conversao quando a conversão já veio de um callback antes (write-once)' do
    original_conversao = 1.day.ago.change(usec: 0)
    lead.update!(conversao_em: original_conversao, tipo_conversao: 'callback')
    stub_create_event

    perform

    lead.reload
    expect(lead.conversao_em).to eq(original_conversao)
    expect(lead.tipo_conversao).to eq('callback')
    expect(lead.agendamento_status).to eq('confirmado')
  end

  # CP-04 -- P1-018-04 (SSOT §16.4): callback pendente substituído por reunião.
  describe 'callback pendente seguido de reunião' do
    before { lead.update!(pending_callback_attributes) }

    it 'Calendar falha: callback continua pendente, sem confirmação falsa' do
      stub_create_event(status: 422, body: { error: 'Calendário inválido' })

      perform

      lead.reload
      expect(lead.agendamento_status).to eq('callback_registrado')
      expect(lead.calendar_event_id).to be_nil
      expect(lead.etapa_prospect).to eq('qualificado')
      expect(lead.conversao_em).to be_nil
    end

    it 'Calendar confirma: Agendado real, reunião é a conversão e o callback fica no histórico' do
      OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'callback_registrado', source: 'lavinia', metadata: {})
      stub_create_event

      perform

      lead.reload
      expect(lead.agendamento_status).to eq('confirmado')
      expect(lead.calendar_event_id).to eq('evt_123')
      expect(lead.agendado_em).to be_present
      expect(lead.etapa_prospect).to eq('agendado')
      expect(lead.tipo_conversao).to eq('agendamento')
      expect(OperationalEngine::LeadEvent.where(lead: lead).pluck(:event_type)).to include('callback_registrado', 'reuniao_agendada')
    end
  end
end
