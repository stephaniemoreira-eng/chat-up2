require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Sales::Stages', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  before { account.enable_features!(:sales_pipeline) }

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/{pipeline.id}/stages' do
    it 'returns unauthorized for an unauthenticated user' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the feature is disabled' do
      account.disable_features!(:sales_pipeline)

      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns stages ordered by position, scoped to the pipeline' do
      second = create(:sales_stage, pipeline: pipeline)
      first = create(:sales_stage, pipeline: pipeline, position: -1)
      create(:sales_stage, pipeline: create(:sales_pipeline, account: account))

      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([first.id, second.id])
    end

    it 'returns not_found when the pipeline belongs to another account' do
      other_pipeline = create(:sales_pipeline, account: create(:account))

      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{other_pipeline.id}/stages", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/{pipeline.id}/stages/{id}' do
    let(:stage) { create(:sales_stage, pipeline: pipeline) }

    it 'returns the stage' do
      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['id']).to eq(stage.id)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/{pipeline.id}/stages' do
    let(:valid_params) { { stage: { name: 'Qualificado', probability: 25 } } }

    it 'creates a stage when the user is an administrator' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", params: valid_params, headers: admin.create_new_auth_token,
                                                                                   as: :json
      end.to change(Sales::Stage, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['name']).to eq('Qualificado')
    end

    it 'returns unauthorized when the user is an agent' do
      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unprocessable_entity for invalid params' do
      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
           params: { stage: { name: '' } },
           headers: admin.create_new_auth_token,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/pipelines/{pipeline.id}/stages/{id}' do
    let(:stage) { create(:sales_stage, pipeline: pipeline) }

    it 'updates the stage when the user is an administrator' do
      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
            params: { stage: { name: 'Updated name' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.name).to eq('Updated name')
    end

    it 'returns unauthorized when the user is an agent' do
      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
            params: { stage: { name: 'Updated name' } },
            headers: agent.create_new_auth_token,
            as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/pipelines/{pipeline.id}/stages/{id}' do
    let!(:stage) { create(:sales_stage, pipeline: pipeline) }

    it 'destroys the stage when the user is an administrator' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Sales::Stage, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it 'returns unauthorized when the user is an agent' do
      delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/{pipeline.id}/stages/reorder' do
    it 'reorders stages when the user is an administrator' do
      first = create(:sales_stage, pipeline: pipeline)
      second = create(:sales_stage, pipeline: pipeline)

      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/reorder",
           params: { positions_hash: { first.id => 1, second.id => 0 } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(0)
    end

    it 'returns unauthorized when the user is an agent' do
      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/reorder",
           params: { positions_hash: {} },
           headers: agent.create_new_auth_token,
           as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
