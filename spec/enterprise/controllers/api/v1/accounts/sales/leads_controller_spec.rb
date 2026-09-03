require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Sales::Leads', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:stage) { create(:sales_stage, pipeline: pipeline) }
  let(:contact) { create(:contact, account: account) }

  before { account.enable_features!(:sales_pipeline) }

  describe 'GET /api/v1/accounts/{account.id}/crm/leads' do
    it 'returns unauthorized for an unauthenticated user' do
      get "/api/v1/accounts/#{account.id}/crm/leads"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the feature is disabled' do
      account.disable_features!(:sales_pipeline)

      get "/api/v1/accounts/#{account.id}/crm/leads", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns leads ordered by position' do
      second = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
      first = create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline, stage: stage, position: -1)

      get "/api/v1/accounts/#{account.id}/crm/leads", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([first.id, second.id])
    end

    it 'does not return leads from other accounts' do
      create(:sales_lead)
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)

      get "/api/v1/accounts/#{account.id}/crm/leads", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([lead.id])
    end

    it 'filters by pipeline_id, stage_id and assignee_id' do
      other_stage = create(:sales_stage, pipeline: pipeline)
      matching = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage, assignee: admin)
      create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline, stage: other_stage)

      get "/api/v1/accounts/#{account.id}/crm/leads",
          params: { pipeline_id: pipeline.id, stage_id: stage.id, assignee_id: admin.id },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([matching.id])
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/leads/{id}' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }

    it 'returns the lead' do
      get "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['id']).to eq(lead.id)
      expect(response.parsed_body['payload']['sales_pipeline_id']).to eq(pipeline.id)
      expect(response.parsed_body['payload']['contact_name']).to eq(contact.name)
      expect(response.parsed_body['payload']['contact_email']).to eq(contact.email)
    end

    it 'omits scan fields when the lead never went through the Scan' do
      get "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['scan_status']).to be_nil
      expect(response.parsed_body['payload']).not_to have_key('scan_score')
    end

    it 'includes the Scan breakdown when the linked prospecting result finished' do
      search = account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP')
      search.results.create!(
        account: account, place_id: 'p1', lead: lead,
        scan_status: 'concluido', scan_score: 83, scan_faixa: 'revisao_prioritaria',
        scan_pilares: { website: 25, maps: 26, instagram: 21, icp: 11 }
      )

      get "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['scan_status']).to eq('concluido')
      expect(payload['scan_score']).to eq(83)
      expect(payload['scan_faixa']).to eq('revisao_prioritaria')
      expect(payload['scan_pilares']).to eq('website' => 25, 'maps' => 26, 'instagram' => 21, 'icp' => 11)
    end

    it 'reports the Scan status as erro without a score when the scan failed' do
      search = account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP')
      search.results.create!(account: account, place_id: 'p1', lead: lead, scan_status: 'erro')

      get "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['scan_status']).to eq('erro')
      expect(payload['scan_score']).to be_nil
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/leads' do
    let(:valid_params) { { lead: { contact_id: contact.id, pipeline_id: pipeline.id, title: 'Negocio novo', value: 500 } } }

    before { stage }

    it 'creates a lead when the user is an agent' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/leads", params: valid_params, headers: agent.create_new_auth_token, as: :json
      end.to change(Sales::Lead, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['title']).to eq('Negocio novo')
    end

    it 'returns unauthorized for an unauthenticated user' do
      post "/api/v1/accounts/#{account.id}/crm/leads", params: valid_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unprocessable_entity for invalid params' do
      post "/api/v1/accounts/#{account.id}/crm/leads",
           params: { lead: { contact_id: contact.id, pipeline_id: pipeline.id, title: '' } },
           headers: admin.create_new_auth_token,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/leads/{id}' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }

    it 'updates the lead when the user is an agent' do
      patch "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}",
            params: { lead: { title: 'Updated title' } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(lead.reload.title).to eq('Updated title')
    end

    it 'does not allow moving the lead to another pipeline via update' do
      other_pipeline = create(:sales_pipeline, account: account)

      patch "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}",
            params: { lead: { pipeline_id: other_pipeline.id } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(lead.reload.sales_pipeline_id).to eq(pipeline.id)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/leads/{id}' do
    let!(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }

    it 'destroys the lead when the user is an administrator' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Sales::Lead, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it 'returns unauthorized when the user is an agent' do
      delete "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/leads/{id}/move' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }
    let(:target_stage) { create(:sales_stage, :won, pipeline: pipeline) }

    it 'moves the lead to the given stage' do
      post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/move",
           params: { sales_stage_id: target_stage.id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(lead.reload.sales_stage_id).to eq(target_stage.id)
      expect(lead.stage_transitions.count).to eq(1)
    end

    it 'returns not_found when the stage belongs to another pipeline' do
      other_stage = create(:sales_stage, pipeline: create(:sales_pipeline, account: account))

      post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/move",
           params: { sales_stage_id: other_stage.id },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/leads/{id}/link_conversation' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }
    let(:conversation) { create(:conversation, account: account) }

    it 'links the conversation to the lead' do
      post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/link_conversation",
           params: { conversation_id: conversation.id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.sales_lead).to eq(lead)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/leads/{id}/unlink_conversation' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }
    let(:conversation) { create(:conversation, account: account) }

    before { Sales::Leads::LinkConversationService.new(lead: lead, conversation: conversation).perform }

    it 'unlinks the conversation from the lead' do
      delete "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/unlink_conversation",
             params: { conversation_id: conversation.id },
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.sales_lead).to be_nil
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/leads/{id}/timeline' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }

    it 'returns the merged timeline entries' do
      activity = create(:sales_activity, lead: lead, body: 'Resumo atualizado')

      get "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/timeline", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['entries'].first['id']).to eq(activity.id)
      expect(response.parsed_body['payload']['entries'].first['type']).to eq('activity')
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/leads/{id}/update_summary' do
    let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage) }

    it 'updates the lead summary and records an activity' do
      expect do
        patch "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/update_summary",
              params: { summary: 'Cliente pediu proposta' },
              headers: agent.create_new_auth_token,
              as: :json
      end.to change(Sales::Activity, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['summary']).to eq('Cliente pediu proposta')
    end
  end
end
