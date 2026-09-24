require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationalEngine::Tools', type: :request do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number) }

  let(:valid_headers) { { 'Authorization' => "Bearer #{agent_tenant.issued_engine_api_key}" } }

  describe 'autenticação (S-5: servidor-a-servidor, sem sessão)' do
    it 'rejeita sem header Authorization' do
      post "/api/v1/accounts/#{account.id}/operational_engine/tools/register_callback",
           params: { conversation_id: conversation.display_id }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'chave inválida')
    end

    it 'rejeita com a chave errada' do
      post "/api/v1/accounts/#{account.id}/operational_engine/tools/register_callback",
           params: { conversation_id: conversation.display_id }, headers: { 'Authorization' => 'Bearer chave-errada' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita quando a conta não existe' do
      post '/api/v1/accounts/999999/operational_engine/tools/register_callback',
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'a chave de uma conta não autentica em outra (isolamento de tenant)' do
      other_account = create(:account)
      other_tenant = create(:up_sales_agent_tenant, account: other_account)

      post "/api/v1/accounts/#{account.id}/operational_engine/tools/register_callback",
           params: { conversation_id: conversation.display_id }, headers: { 'Authorization' => "Bearer #{other_tenant.issued_engine_api_key}" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'aceita com a chave certa' do
      post "/api/v1/accounts/#{account.id}/operational_engine/tools/register_callback",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true)
    end
  end

  describe 'POST register_callback' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/tools/register_callback",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response.parsed_body).to eq('ok' => true)
      expect(lead.reload.agendamento_status).to eq('callback_registrado')
    end

    it 'devolve ok:false com o motivo quando o service falha' do
      post "/api/v1/accounts/#{account.id}/operational_engine/tools/register_callback",
           params: { conversation_id: -1 }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'conversa não encontrada')
    end
  end

  describe 'GET availability' do
    it 'reflete o resultado do service' do
      get "/api/v1/accounts/#{account.id}/operational_engine/tools/availability",
          headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'agenda não conectada para esta conta')
    end
  end

  describe 'POST schedule_meeting' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/tools/schedule_meeting",
           params: { conversation_id: conversation.display_id, summary: 'Reunião',
                     start: '2026-09-22T14:00:00-03:00', end: '2026-09-22T14:30:00-03:00' },
           headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'agenda não conectada para esta conta')
    end
  end

  describe 'PATCH schedule_meeting/:event_id' do
    it 'reflete o resultado do service' do
      patch "/api/v1/accounts/#{account.id}/operational_engine/tools/schedule_meeting/evt_123",
            params: { conversation_id: conversation.display_id, start: '2026-09-23T15:00:00-03:00' },
            headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'este lead não tem uma reunião confirmada com esse event_id')
    end
  end

  describe 'DELETE schedule_meeting/:event_id' do
    it 'reflete o resultado do service' do
      delete "/api/v1/accounts/#{account.id}/operational_engine/tools/schedule_meeting/evt_123",
             params: { conversation_id: conversation.display_id },
             headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'este lead não tem uma reunião confirmada com esse event_id')
    end
  end

  # CP-10 (P1-VAL-03; SSOT §23.1, 28.14): as ferramentas de agenda da Lavínia no modo agent são
  # idempotentes pela identidade do turno e aceitam a forma sem :event_id.
  describe 'ferramentas de agenda do modo agent (CP-10)' do
    let(:calendar_base) { 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events' }
    let(:base_path) { "/api/v1/accounts/#{account.id}/operational_engine/tools/schedule_meeting" }
    let(:schedule_params) do
      { conversation_id: conversation.display_id, summary: 'Reunião', turn_id: 'msg:900',
        start: '2026-09-22T14:00:00-03:00', end: '2026-09-22T14:30:00-03:00' }
    end

    before do
      agent_tenant.update!(calendar_integration_instance_id: 'instance-1')
      lead.update!(upsales_contact_id: contact.id)
    end

    it 'repetir Criar evento no mesmo turno não cria um segundo evento' do
      stub_request(:post, calendar_base)
        .to_return(status: 200, body: { event: { 'id' => 'evt_123' } }.to_json, headers: { 'Content-Type' => 'application/json' })

      post base_path, params: schedule_params, headers: valid_headers, as: :json
      expect(response.parsed_body).to eq('ok' => true, 'event_id' => 'evt_123')

      post base_path, params: schedule_params, headers: valid_headers, as: :json
      expect(response.parsed_body).to eq('ok' => true, 'event_id' => 'evt_123', 'replay' => true)

      expect(a_request(:post, calendar_base)).to have_been_made.once
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'reuniao_agendada').count).to eq(1)
      expect(lead.reload.agendamento_status).to eq('confirmado')
    end

    it 'falha do Calendar: ok:false e nada confirmado (28.15)' do
      stub_request(:post, calendar_base)
        .to_return(status: 422, body: { error: 'Calendário inválido' }.to_json, headers: { 'Content-Type' => 'application/json' })

      post base_path, params: schedule_params, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'Calendário inválido')
      expect(lead.reload.agendamento_status).to eq('nao_iniciado')
    end

    it 'reunião já confirmada: devolve ja_existia sem criar outro evento' do
      lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_old', etapa_prospect: 'agendado', agendado_em: Time.current)

      post base_path, params: schedule_params.merge(turn_id: 'msg:901'), headers: valid_headers, as: :json

      expect(response.parsed_body).to eq('ok' => true, 'event_id' => 'evt_old', 'ja_existia' => true)
      expect(a_request(:post, calendar_base)).not_to have_been_made
    end

    it 'PATCH sem :event_id reagenda a reunião confirmada do lead' do
      lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_old', etapa_prospect: 'agendado', agendado_em: Time.current)
      stub_request(:patch, "#{calendar_base}/evt_old")
        .to_return(status: 200, body: { event: { 'id' => 'evt_old' } }.to_json, headers: { 'Content-Type' => 'application/json' })

      patch base_path, params: { conversation_id: conversation.display_id, turn_id: 'msg:902', start: '2026-09-23T15:00:00-03:00',
                                 end: '2026-09-23T15:30:00-03:00' }, headers: valid_headers, as: :json

      expect(response.parsed_body).to eq('ok' => true, 'event_id' => 'evt_old')
    end

    it 'DELETE sem :event_id cancela a reunião confirmada do lead; repetir no turno não cancela 2x' do
      lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_old', etapa_prospect: 'agendado', agendado_em: Time.current)
      stub_request(:delete, "#{calendar_base}/evt_old")
        .to_return(status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      2.times { delete base_path, params: { conversation_id: conversation.display_id, turn_id: 'msg:903' }, headers: valid_headers, as: :json }

      expect(response.parsed_body).to eq('ok' => true, 'replay' => true)
      expect(a_request(:delete, "#{calendar_base}/evt_old")).to have_been_made.once
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'reuniao_cancelada').count).to eq(1)
    end

    it 'lead em atendimento humano: Criar evento recusado sem chamar o Calendar' do
      lead.update!(modo_atendimento: 'humano')

      post base_path, params: schedule_params, headers: valid_headers, as: :json

      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'lead em atendimento humano')
      expect(a_request(:post, calendar_base)).not_to have_been_made
    end
  end
end
