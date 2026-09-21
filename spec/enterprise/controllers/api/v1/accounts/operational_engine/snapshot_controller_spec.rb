require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationalEngine::Snapshot', type: :request do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, nome: 'Danilo') }

  let(:valid_headers) { { 'Authorization' => "Bearer #{agent_tenant.engine_api_key}" } }

  describe 'GET health' do
    it 'usa a mesma autenticação servidor-a-servidor do Contrato B (S-5)' do
      get "/api/v1/accounts/#{account.id}/operational_engine/health", as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'chave inválida')
    end

    it 'confirma que o Supabase está alcançável, não só que a chave é válida' do
      get "/api/v1/accounts/#{account.id}/operational_engine/health", headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true)
    end
  end

  describe 'GET snapshot' do
    it 'devolve o Snapshot (§12.3) do lead da conversa' do
      get "/api/v1/accounts/#{account.id}/operational_engine/snapshot",
          params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['ok']).to eq(true)
      expect(body['snapshot']['identidade']['nome']).to eq('Danilo')
      expect(body['snapshot']['identidade']['telefone']).to eq(contact.phone_number)
      expect(body['snapshot']['source']).to eq('engine')
    end

    it 'devolve ok:false quando a conversa não resolve nenhum lead' do
      get "/api/v1/accounts/#{account.id}/operational_engine/snapshot",
          params: { conversation_id: -1 }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'conversa não encontrada')
    end

    it 'rejeita sem autenticação, igual ao ToolsController' do
      get "/api/v1/accounts/#{account.id}/operational_engine/snapshot",
          params: { conversation_id: conversation.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
