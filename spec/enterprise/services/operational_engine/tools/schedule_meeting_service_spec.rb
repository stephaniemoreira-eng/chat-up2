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

  def stub_calendar_events(events = [])
    stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events')
      .with(query: hash_including('timeMin' => '2026-09-22T14:00:00-03:00', 'timeMax' => '2026-09-22T14:30:00-03:00'))
      .to_return(status: 200, body: { events: events }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_create_event(status: 200, body: { event: { 'id' => 'evt_123', 'htmlLink' => 'https://calendar.google.com/evt_123' } }, events: [])
    stub_calendar_events(events)
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

    expect(result).to eq(ok: false, reason: 'agenda não conectada para esta conta', falha_calendar: true)
  end

  describe 'disponibilidade no instante da escrita (F-RT-01)' do
    let(:calendar_url) { 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events' }

    def busy_event(starts_at:, ends_at:)
      { 'id' => 'busy_1', 'start' => { 'dateTime' => starts_at }, 'end' => { 'dateTime' => ends_at } }
    end

    it 'recusa sobreposição total sem criar evento nem confirmar' do
      stub_calendar_events([busy_event(starts_at: '2026-09-22T14:00:00-03:00', ends_at: '2026-09-22T14:30:00-03:00')])

      expect(perform).to eq(ok: false, reason: 'horário indisponível na agenda', falha_calendar: true)
      expect(a_request(:post, calendar_url)).not_to have_been_made
      expect(lead.reload.agendamento_status).to eq('nao_iniciado')
      expect(lead.calendar_event_id).to be_nil
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'reuniao_agendada')).to be_empty
    end

    it 'recusa sobreposição parcial sem criar evento' do
      stub_calendar_events([busy_event(starts_at: '2026-09-22T13:45:00-03:00', ends_at: '2026-09-22T14:15:00-03:00')])

      expect(perform).to eq(ok: false, reason: 'horário indisponível na agenda', falha_calendar: true)
      expect(a_request(:post, calendar_url)).not_to have_been_made
    end

    it 'permite intervalo adjacente, sem sobreposição' do
      adjacent = busy_event(starts_at: '2026-09-22T13:30:00-03:00', ends_at: '2026-09-22T14:00:00-03:00')
      stub_create_event(events: [adjacent])

      expect(perform).to eq(ok: true, event_id: 'evt_123')
    end

    it 'falha fechada quando não consegue reler a agenda' do
      stub_request(:get, calendar_url)
        .with(query: hash_including('timeMin' => '2026-09-22T14:00:00-03:00', 'timeMax' => '2026-09-22T14:30:00-03:00'))
        .to_return(status: 503, body: { error: 'Calendar indisponível' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(perform).to eq(ok: false, reason: 'Calendar indisponível', falha_calendar: true)
      expect(a_request(:post, calendar_url)).not_to have_been_made
      expect(lead.reload.agendamento_status).to eq('nao_iniciado')
      expect(lead.calendar_event_id).to be_nil
    end
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

    expect(result).to eq(ok: false, reason: 'Calendário inválido', falha_calendar: true)
    lead.reload
    expect(lead.agendamento_status).to eq('nao_iniciado')
    expect(lead.calendar_event_id).to be_nil
    expect(lead.conversao_em).to be_nil
  end

  it 'é idempotente: uma segunda chamada num lead já confirmado não cria outro evento' do
    lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_already', etapa_prospect: 'agendado', agendado_em: Time.current)

    result = perform

    expect(result).to eq(ok: true, event_id: 'evt_already', ja_existia: true)
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

  # CP-09 -- P1-VAL-05 (SSOT §16.1, §13.2, §13.3, §8.4).
  describe 'reunião confirmada qualifica e cria/mantém a oportunidade Comercial' do
    def events(type)
      OperationalEngine::LeadEvent.where(lead: lead, event_type: type)
    end

    before { lead.update!(etapa_prospect: 'em_conversa', etapa_entrou_em: 1.day.ago) }

    it 'lead ainda não qualificado: qualifica no mesmo lock antes do Agendado' do
      stub_create_event

      perform

      lead.reload
      expect(lead.qualificacao_status).to eq('qualificado')
      expect(lead.qualificado_em).to be_present
      expect(lead.etapa_prospect).to eq('agendado')
      expect(events('lead_qualificado').count).to eq(1)
      expect(events('etapa_alterada').first.metadata).to include('de' => 'em_conversa', 'para' => 'qualificado')
    end

    it 'cria a oportunidade Comercial com oportunidade_criada, sem handoff' do
      stub_create_event

      perform

      lead.reload
      expect(lead.etapa_comercial).to eq('oportunidade')
      expect(lead.resultado_comercial).to eq('em_aberto')
      expect([lead.frente_operacional, lead.modo_atendimento]).to eq(%w[prospeccao lavinia])
      expect(events('oportunidade_criada').first.metadata).to include('etapa_comercial' => 'oportunidade', 'motivo' => 'reuniao_agendada')
    end

    it 'projeta o card Comercial em Oportunidade' do
      stub_create_event

      perform

      comercial = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'comercial' })
      expect(comercial.stage.engine_stage_key).to eq('oportunidade')
    end

    it 'lead já qualificado: não regrava qualificado_em nem duplica lead_qualificado' do
      qualificado_em = 2.days.ago.change(usec: 0)
      lead.update!(etapa_prospect: 'qualificado', qualificacao_status: 'qualificado', qualificado_em: qualificado_em)
      stub_create_event

      perform

      expect(lead.reload.qualificado_em).to eq(qualificado_em)
      expect(events('lead_qualificado')).to be_empty
    end

    it 'mantém uma oportunidade que já existia (callback pendente) sem rebaixar nem duplicar o evento' do
      lead.update!(pending_callback_attributes.merge(etapa_comercial: 'em_acompanhamento'))
      stub_create_event

      perform

      expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
      expect(events('oportunidade_criada')).to be_empty
    end

    it 'Calendar falha: não qualifica nem cria oportunidade (§23.3)' do
      stub_create_event(status: 422, body: { error: 'Calendário inválido' })

      perform

      lead.reload
      expect(lead.qualificacao_status).to eq('em_qualificacao')
      expect(lead.etapa_prospect).to eq('em_conversa')
      expect(lead.etapa_comercial).to be_nil
      expect(events('oportunidade_criada')).to be_empty
    end

    it 'repetir a confirmação não duplica eventos (idempotência)' do
      stub_create_event
      perform

      expect { perform }.not_to change(OperationalEngine::LeadEvent, :count)
    end
  end

  # CP-10 (P1-VAL-03; SSOT §12.4, §23.2, 28.19): agora é a ferramenta "Criar evento" da Lavínia --
  # as guardas valem ANTES do Calendar, então nenhum evento real nasce para um lead bloqueado.
  describe 'guardas da Lavínia (CP-10)' do
    let(:calendar_url) { 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events' }

    before { stub_create_event }

    it 'lead em atendimento humano: recusa sem criar evento nem confirmar' do
      lead.update!(modo_atendimento: 'humano')

      expect(perform).to eq(ok: false, reason: 'lead em atendimento humano')
      expect(a_request(:post, calendar_url)).not_to have_been_made
      expect(lead.reload.agendamento_status).to eq('nao_iniciado')
      expect(lead.calendar_event_id).to be_nil
    end

    it 'lead em não-contatar: recusa sem criar evento' do
      lead.update!(nao_contatar: true)

      expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
      expect(a_request(:post, calendar_url)).not_to have_been_made
    end

    it 'lead encerrado: recusa sem criar evento' do
      lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')

      expect(perform).to eq(ok: false, reason: 'lead encerrado')
      expect(a_request(:post, calendar_url)).not_to have_been_made
    end

    it 'humano também vence a resposta idempotente de reunião já confirmada' do
      lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_already', etapa_prospect: 'agendado',
                   agendado_em: Time.current, modo_atendimento: 'humano')

      expect(perform).to eq(ok: false, reason: 'lead em atendimento humano')
    end
  end
end
