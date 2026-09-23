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

    it 'reports the Scan status as pendente while the scan is still running' do
      search = account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP')
      search.results.create!(account: account, place_id: 'p1', lead: lead)

      get "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['scan_status']).to eq('pendente')
      expect(payload).not_to have_key('scan_score')
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

    it 'blocks a manual drag into a stage marked engine_stage_key agendado (SSOT §21.2)' do
      agendado_stage = create(:sales_stage, pipeline: pipeline, engine_stage_key: 'agendado')

      post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/move",
           params: { sales_stage_id: agendado_stage.id },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(lead.reload.sales_stage_id).to eq(stage.id)
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

  describe 'acoes humanas do Kanban Comercial (Fase 9, §21.2)' do
    # CP-05 (P2-025-01): oportunidade Comercial completa (handoff real), não etapa_comercial solta.
    def build_engine_lead(**overrides)
      OperationalEngine::Lead.create!({
        conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
        **comercial_opportunity_attributes
      }.merge(overrides))
    end

    def synced_sales_lead(engine_lead)
      OperationalEngine::ComercialProjectionSync.call(engine_lead)
      Sales::Lead.find_by!(operational_lead_id: engine_lead.lead_id)
    end

    describe 'POST .../register_callback_realizado' do
      it 'marca o callback como realizado' do
        engine_lead = build_engine_lead(agendamento_status: 'callback_registrado')
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_callback_realizado",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.agendamento_status).to eq('callback_realizado')
      end

      it 'retorna unprocessable_entity quando nao ha callback pendente' do
        engine_lead = build_engine_lead
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_callback_realizado",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'retorna unprocessable_entity quando o card nao esta vinculado a um lead do Engine' do
        lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_callback_realizado",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe 'POST .../register_no_show' do
      it 'registra o no-show' do
        engine_lead = build_engine_lead
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_no_show",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.no_show_em).to be_present
      end
    end

    describe 'POST .../set_propensao' do
      it 'grava a propensao informada' do
        engine_lead = build_engine_lead
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/set_propensao",
             params: { propensao_fechamento: 'quente' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.propensao_fechamento).to eq('quente')
      end
    end

    describe 'POST .../register_resultado_comercial' do
      it 'marca a oportunidade como ganho' do
        engine_lead = build_engine_lead(etapa_comercial: 'em_acompanhamento')
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_resultado_comercial",
             params: { resultado_comercial: 'ganho' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.resultado_comercial).to eq('ganho')
        expect(response.parsed_body['payload']['sales_stage_id']).to eq(
          Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform.stages.find_by!(engine_stage_key: 'ganho').id
        )
      end

      it 'marca a oportunidade como perdido com motivo' do
        engine_lead = build_engine_lead(etapa_comercial: 'em_acompanhamento')
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_resultado_comercial",
             params: { resultado_comercial: 'perdido', motivo_perda: 'sem orcamento' },
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.motivo_perda).to eq('sem orcamento')
      end

      it 'retorna unprocessable_entity ao tentar resolver de novo uma oportunidade ja resolvida' do
        engine_lead = build_engine_lead(resultado_comercial: 'ganho', etapa_comercial: 'ganho')
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_resultado_comercial",
             params: { resultado_comercial: 'perdido' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(engine_lead.reload.resultado_comercial).to eq('ganho')
      end

      # CP-05 (P1-025-02): chamada direta fora da sequência §8.4 é recusada no backend.
      it 'retorna unprocessable_entity ao resolver direto de Oportunidade, sem mexer no Engine' do
        engine_lead = build_engine_lead
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/register_resultado_comercial",
             params: { resultado_comercial: 'ganho' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('transição Comercial não permitida')
        expect(engine_lead.reload.resultado_comercial).to eq('em_aberto')
      end
    end

    # CP-05 (P1-025-02): guardas de backend -- valem mesmo se o botão não estivesse visível.
    describe 'contexto Comercial inválido' do
      it 'recusa no-show/propensão/resultado num lead sem oportunidade Comercial' do
        engine_lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110030', upsales_contact_id: contact.id)
        comercial = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
        card = create(:sales_lead, account: account, contact: contact, pipeline: comercial, stage: comercial.stages.first,
                                   operational_lead_id: engine_lead.lead_id)

        %w[register_no_show set_propensao register_resultado_comercial].each do |action|
          post "/api/v1/accounts/#{account.id}/crm/leads/#{card.id}/#{action}",
               params: { propensao_fechamento: 'quente', resultado_comercial: 'ganho' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
        end
        expect(engine_lead.reload.attributes.values_at('no_show_em', 'propensao_fechamento', 'resultado_comercial'))
          .to eq([nil, 'nao_classificado', 'em_aberto'])
      end

      it 'o card Prospect do mesmo lead não serve de atalho para ações Comerciais' do
        engine_lead = build_engine_lead(etapa_comercial: 'em_acompanhamento')
        OperationalEngine::SalesProjectionSync.call(engine_lead)
        prospect_card = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: engine_lead.lead_id,
                                                              sales_pipelines: { engine_kind: 'prospect' })

        post "/api/v1/accounts/#{account.id}/crm/leads/#{prospect_card.id}/register_resultado_comercial",
             params: { resultado_comercial: 'ganho' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(engine_lead.reload.resultado_comercial).to eq('em_aberto')
      end
    end

    # CP-05 (P1-023-03, §21.2): drag num card Comercial gerido pelo Engine vira ação do Engine.
    describe 'POST .../move num card Comercial gerido pelo Engine' do
      def stage_for(key)
        Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform.stages.find_by!(engine_stage_key: key)
      end

      it 'Oportunidade → Em acompanhamento passa pelo Engine (etapa + evento) antes de mover o card' do
        engine_lead = build_engine_lead
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/move",
             params: { sales_stage_id: stage_for('em_acompanhamento').id }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.etapa_comercial).to eq('em_acompanhamento')
        expect(engine_lead.events.find_by(event_type: 'etapa_alterada')).to be_present
        expect(lead.reload.sales_stage_id).to eq(stage_for('em_acompanhamento').id)
      end

      it 'drag para Ganho é recusado e o card não diverge do Engine' do
        engine_lead = build_engine_lead(etapa_comercial: 'em_acompanhamento')
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/move",
             params: { sales_stage_id: stage_for('ganho').id }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(engine_lead.reload.etapa_comercial).to eq('em_acompanhamento')
        expect(lead.reload.sales_stage_id).to eq(stage_for('em_acompanhamento').id)
      end

      it 'drag num card Prospect gerido pelo Engine é recusado' do
        engine_lead = build_engine_lead(**confirmed_meeting_attributes)
        OperationalEngine::SalesProjectionSync.call(engine_lead)
        prospect_card = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: engine_lead.lead_id,
                                                              sales_pipelines: { engine_kind: 'prospect' })
        qualificado = prospect_card.pipeline.stages.find_by!(engine_stage_key: 'qualificado')

        post "/api/v1/accounts/#{account.id}/crm/leads/#{prospect_card.id}/move",
             params: { sales_stage_id: qualificado.id }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(prospect_card.reload.stage.engine_stage_key).to eq('agendado')
      end
    end

    describe 'POST .../advance_etapa_comercial' do
      it 'move a oportunidade para Em acompanhamento pelo Engine' do
        engine_lead = build_engine_lead
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/advance_etapa_comercial",
             params: { etapa_comercial: 'em_acompanhamento' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.etapa_comercial).to eq('em_acompanhamento')
      end
    end

    # CP-05 (P2-025-03, §20.3).
    describe 'POST .../remove_no_show' do
      it 'remove a tag NO-SHOW preservando o evento histórico' do
        engine_lead = build_engine_lead(etapa_comercial: 'em_acompanhamento')
        lead = synced_sales_lead(engine_lead)
        OperationalEngine::RegisterNoShowService.call!(lead: engine_lead, user_id: agent.id)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/remove_no_show",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']['custom_attributes']['engine_tags']).not_to include('no_show')
        expect(engine_lead.events.where(event_type: 'reuniao_no_show').count).to eq(1)
      end
    end
  end

  describe 'Assumir/Devolver (Fase 3, §18.2/§18.3, §21.2)' do
    def build_engine_lead(**overrides)
      OperationalEngine::Lead.create!({
        conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id
      }.merge(overrides))
    end

    def synced_sales_lead(engine_lead)
      OperationalEngine::SalesProjectionSync.call(engine_lead)
      Sales::Lead.find_by!(operational_lead_id: engine_lead.lead_id)
    end

    describe 'POST .../assumir' do
      it 'poe o lead em modo humano com o agente autenticado como responsavel' do
        engine_lead = build_engine_lead(modo_atendimento: 'lavinia')
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/assumir",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.modo_atendimento).to eq('humano')
        expect(engine_lead.responsavel_atual_id).to eq(agent.id)
        expect(response.parsed_body['payload']['custom_attributes']['engine_tags']).to eq(['humano'])
      end
    end

    describe 'POST .../devolver' do
      it 'volta o lead pra lavinia' do
        engine_lead = build_engine_lead(modo_atendimento: 'humano', responsavel_atual_id: agent.id)
        lead = synced_sales_lead(engine_lead)

        post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/devolver",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(engine_lead.reload.modo_atendimento).to eq('lavinia')
        expect(engine_lead.responsavel_atual_id).to be_nil
        expect(response.parsed_body['payload']['custom_attributes']['engine_tags']).to eq(['lavinia'])
      end
    end

    it 'retorna unprocessable_entity quando o card nao esta vinculado a um lead do Engine' do
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)

      post "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}/assumir",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
