require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationalEngine::Tools', type: :request do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number) }

  let(:valid_headers) { { 'Authorization' => "Bearer #{agent_tenant.engine_api_key}" } }

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
           params: { conversation_id: conversation.display_id }, headers: { 'Authorization' => "Bearer #{other_tenant.engine_api_key}" }, as: :json

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
end
