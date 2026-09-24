require 'rails_helper'

# CP-11 (P1-VAL-08, P1-VAL-09; SSOT §22, 28.34, 28.40).
RSpec.describe 'Api::V1::Accounts::Sales::ProspectDashboard', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/prospect_dashboard" }

  before { account.enable_features!(:sales_pipeline) }

  def engine_lead!(conta_id: account.id, **attrs)
    OperationalEngine::Lead.create!(conta_id: conta_id, telefone: "+551398#{SecureRandom.random_number(10**7).to_s.rjust(7, '0')}", **attrs)
  end

  def inbound!(entrada, **attrs)
    engine_lead!(modo_entrada: 'inbound', etapa_prospect: 'em_conversa', entrada_operacao_em: tz.parse(entrada), **attrs)
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/prospect_dashboard' do
    it 'exige autenticação' do
      get url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'calcula sobre o Engine da própria conta, com o mês corrente em America/Sao_Paulo como coorte padrão' do
      inbox = create(:inbox, account: account, name: 'Prospecção')
      inbound!('2026-09-02 10:00', inbox_entrada_id: inbox.id, origem_lead: 'inbound_direto', segmento: 'hotel')
      inbound!('2026-08-20 10:00')
      engine_lead!(conta_id: account.id + 1, modo_entrada: 'inbound', etapa_prospect: 'em_conversa', entrada_operacao_em: tz.parse('2026-09-03'))

      travel_to(tz.parse('2026-09-15 12:00')) { get url, headers: agent.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['coorte']).to include('data_inicial' => '2026-09-01', 'data_final' => '2026-09-30', 'modo' => 'consolidado')
      expect(body['big_numbers']['leads_iniciados']).to eq(1)
      expect(body['opcoes_filtro']['inboxes_entrada']).to eq([{ 'id' => inbox.id, 'nome' => 'Prospecção' }])
      expect(body['opcoes_filtro']['origens_lead']).to eq(['inbound_direto'])
      expect(body['opcoes_filtro']['segmentos']).to eq(['hotel'])
    end

    it 'aplica os filtros oficiais recebidos' do
      inbound!('2026-08-05 10:00', segmento: 'hotel')
      inbound!('2026-08-06 10:00', segmento: 'clinica')

      get url, params: { data_inicial: '2026-08-01', data_final: '2026-08-31', modo: 'inbound', segmento: 'hotel' },
               headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['big_numbers']['leads_iniciados']).to eq(1)
      expect(response.parsed_body['coorte']).to include('modo' => 'inbound', 'segmento' => 'hotel')
    end

    it 'devolve 422 para filtro inválido' do
      get url, params: { modo: 'humano' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('modo')
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/leads/summary (P1-VAL-09)' do
    let(:prospect) { create(:sales_pipeline, account: account) }
    let(:comercial) { create(:sales_pipeline, account: account) }

    it 'conta cada lead do Engine uma vez, mesmo com card Prospect e card Comercial' do
      contact = create(:contact, account: account)
      duplicado = SecureRandom.uuid
      create(:sales_lead, account: account, contact: contact, pipeline: prospect, operational_lead_id: duplicado)
      create(:sales_lead, account: account, contact: contact, pipeline: comercial, operational_lead_id: duplicado, status: :won)
      create(:sales_lead, account: account, pipeline: prospect, operational_lead_id: SecureRandom.uuid)
      create(:sales_lead, account: account, pipeline: prospect)
      create(:sales_lead, account: account, pipeline: prospect, status: :won)

      get "/api/v1/accounts/#{account.id}/crm/leads/summary", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['leads_count']).to eq(4)
      expect(response.parsed_body['deals_won_count']).to eq(2)
    end
  end
end
