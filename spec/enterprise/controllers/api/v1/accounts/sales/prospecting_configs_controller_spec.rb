require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Sales::ProspectingConfigs', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  before { account.enable_features!(:sales_pipeline) }

  describe 'GET /api/v1/accounts/{account.id}/crm/prospecting/configs' do
    it 'returns unauthorized for an unauthenticated user' do
      get "/api/v1/accounts/#{account.id}/crm/prospecting/configs"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the account configs' do
      config = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline)
      create(:account).sales_prospecting_configs.create!(business_type: 'x', city: 'y', state: 'SP',
                                                           pipeline: create(:sales_pipeline))

      get "/api/v1/accounts/#{account.id}/crm/prospecting/configs", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([config.id])
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/prospecting/configs' do
    let(:valid_params) { { business_type: 'academia', city: 'Santos', state: 'SP', pipeline_id: pipeline.id } }

    it 'creates a config when the user is an agent' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/prospecting/configs", params: valid_params, headers: agent.create_new_auth_token, as: :json
      end.to change(Sales::ProspectingConfig, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['business_type']).to eq('academia')
      expect(response.parsed_body['payload']['active']).to be(true)
    end

    it 'returns unprocessable_entity for invalid params' do
      post "/api/v1/accounts/#{account.id}/crm/prospecting/configs",
           params: { business_type: '', city: 'Santos', state: 'SP', pipeline_id: pipeline.id },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/prospecting/configs/{id}' do
    let(:config) { account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline) }

    it 'toggles active without touching the other fields' do
      patch "/api/v1/accounts/#{account.id}/crm/prospecting/configs/#{config.id}",
            params: { active: false }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(config.reload.active).to be(false)
      expect(config.business_type).to eq('academia')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/prospecting/configs/{id}' do
    let!(:config) { account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline) }

    it 'destroys the config when the user is an administrator' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm/prospecting/configs/#{config.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Sales::ProspectingConfig, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it 'returns unauthorized when the user is an agent' do
      delete "/api/v1/accounts/#{account.id}/crm/prospecting/configs/#{config.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
