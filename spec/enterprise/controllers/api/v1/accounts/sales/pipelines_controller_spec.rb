require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Sales::Pipelines', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { account.enable_features!(:sales_pipeline) }

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines' do
    it 'returns unauthorized for an unauthenticated user' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the feature is disabled' do
      account.disable_features!(:sales_pipeline)

      get "/api/v1/accounts/#{account.id}/crm/pipelines", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns pipelines ordered by position' do
      second = create(:sales_pipeline, account: account)
      first = create(:sales_pipeline, account: account, position: -1)

      get "/api/v1/accounts/#{account.id}/crm/pipelines", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([first.id, second.id])
    end

    it 'does not return pipelines from other accounts' do
      create(:sales_pipeline, account: create(:account))
      pipeline = create(:sales_pipeline, account: account)

      get "/api/v1/accounts/#{account.id}/crm/pipelines", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([pipeline.id])
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/{id}' do
    let(:pipeline) { create(:sales_pipeline, account: account) }

    it 'returns the pipeline' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['id']).to eq(pipeline.id)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines' do
    let(:valid_params) { { pipeline: { name: 'Comercial', description: 'Main pipeline' } } }

    it 'creates a pipeline when the user is an administrator' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/pipelines", params: valid_params, headers: admin.create_new_auth_token, as: :json
      end.to change(Sales::Pipeline, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['name']).to eq('Comercial')
    end

    it 'returns unauthorized when the user is an agent' do
      post "/api/v1/accounts/#{account.id}/crm/pipelines", params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unprocessable_entity for invalid params' do
      post "/api/v1/accounts/#{account.id}/crm/pipelines", params: { pipeline: { name: '' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/pipelines/{id}' do
    let(:pipeline) { create(:sales_pipeline, account: account) }

    it 'updates the pipeline when the user is an administrator' do
      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
            params: { pipeline: { name: 'Updated name' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(pipeline.reload.name).to eq('Updated name')
    end

    it 'returns unauthorized when the user is an agent' do
      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
            params: { pipeline: { name: 'Updated name' } },
            headers: agent.create_new_auth_token,
            as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/pipelines/{id}' do
    let!(:pipeline) { create(:sales_pipeline, account: account) }

    it 'destroys the pipeline when the user is an administrator' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Sales::Pipeline, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it 'returns unauthorized when the user is an agent' do
      delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/reorder' do
    it 'reorders pipelines when the user is an administrator' do
      first = create(:sales_pipeline, account: account)
      second = create(:sales_pipeline, account: account)

      post "/api/v1/accounts/#{account.id}/crm/pipelines/reorder",
           params: { positions_hash: { first.id => 1, second.id => 0 } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(0)
    end

    it 'returns unauthorized when the user is an agent' do
      post "/api/v1/accounts/#{account.id}/crm/pipelines/reorder", params: { positions_hash: {} }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
