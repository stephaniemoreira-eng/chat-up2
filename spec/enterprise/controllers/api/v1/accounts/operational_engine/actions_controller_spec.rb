require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationalEngine::Actions', type: :request do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number) }

  let(:valid_headers) { { 'Authorization' => "Bearer #{agent_tenant.engine_api_key}" } }

  it 'rejeita sem autenticação, igual às outras rotas do Contrato B' do
    post "/api/v1/accounts/#{account.id}/operational_engine/actions/iniciar_orcamento",
         params: { conversation_id: conversation.id }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'POST iniciar_orcamento' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/iniciar_orcamento",
           params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true)
      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
    end
  end

  describe 'POST iniciar_agendamento' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/iniciar_agendamento",
           params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.agendamento_status).to eq('em_andamento')
    end
  end

  describe 'POST registrar_callback' do
    it 'reflete o resultado do service -- mesma regra da rota tools/register_callback' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/registrar_callback",
           params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.agendamento_status).to eq('callback_registrado')
    end
  end

  describe 'POST handoff_comercial' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/handoff_comercial",
           params: { conversation_id: conversation.id, motivo_handoff: 'avanco_comercial' }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.modo_atendimento).to eq('humano')
    end

    it 'devolve ok:false com motivo_handoff inválido' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/handoff_comercial",
           params: { conversation_id: conversation.id, motivo_handoff: 'invalido' }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'motivo_handoff inválido')
    end
  end

  describe 'POST encerrar_sem_interesse' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/encerrar_sem_interesse",
           params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.motivo_encerramento).to eq('sem_interesse')
    end
  end

  describe 'POST encerrar_nao_qualificado' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/encerrar_nao_qualificado",
           params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.qualificacao_status).to eq('nao_qualificado')
    end
  end

  describe 'POST ativar_nao_contatar' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/ativar_nao_contatar",
           params: { conversation_id: conversation.id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.nao_contatar).to eq(true)
    end
  end

  describe 'conversa não encontrada' do
    it 'devolve ok:false com unprocessable_entity, mesmo formato do ToolsController' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/iniciar_orcamento",
           params: { conversation_id: -1 }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'conversa não encontrada')
    end
  end
end
