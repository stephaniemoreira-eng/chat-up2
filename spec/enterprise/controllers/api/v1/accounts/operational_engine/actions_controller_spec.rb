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
         params: { conversation_id: conversation.display_id }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'POST iniciar_orcamento' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/iniciar_orcamento",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true)
      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
    end
  end

  describe 'POST iniciar_agendamento' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/iniciar_agendamento",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.agendamento_status).to eq('em_andamento')
    end
  end

  describe 'POST registrar_callback' do
    it 'reflete o resultado do service -- mesma regra da rota tools/register_callback' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/registrar_callback",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.agendamento_status).to eq('callback_registrado')
    end
  end

  describe 'POST handoff_comercial' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/handoff_comercial",
           params: { conversation_id: conversation.display_id, motivo_handoff: 'avanco_comercial' }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.modo_atendimento).to eq('humano')
    end

    it 'devolve ok:false com motivo_handoff inválido' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/handoff_comercial",
           params: { conversation_id: conversation.display_id, motivo_handoff: 'invalido' }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'motivo_handoff inválido')
    end
  end

  describe 'POST encerrar_sem_interesse' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/encerrar_sem_interesse",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.motivo_encerramento).to eq('sem_interesse')
    end
  end

  describe 'POST encerrar_nao_qualificado' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/encerrar_nao_qualificado",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(lead.reload.qualificacao_status).to eq('nao_qualificado')
    end
  end

  describe 'POST ativar_nao_contatar' do
    it 'reflete o resultado do service' do
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/ativar_nao_contatar",
           params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

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

  # CP-03 -- P1-021-01: identidade estável do turno.
  describe 'turn_id' do
    def post_action(acao, turn_id)
      post "/api/v1/accounts/#{account.id}/operational_engine/actions/#{acao}",
           params: { conversation_id: conversation.display_id, turn_id: turn_id }, headers: valid_headers, as: :json
    end

    it 'retry do mesmo turno (ex.: depois de timeout) não duplica a mutação nem o evento' do
      2.times { post_action('iniciar_orcamento', 'msg:900') }

      expect(response.parsed_body['ok']).to be(true)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'orcamento_iniciado').count).to eq(1)
    end

    it 'replay tardio do mesmo turno depois de uma mudança legítima não reaplica a ação antiga' do
      post_action('iniciar_agendamento', 'msg:901')
      lead.reload.update!(agendamento_status: 'cancelado')

      post_action('iniciar_agendamento', 'msg:901')

      expect(lead.reload.agendamento_status).to eq('cancelado')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'agendamento_iniciado').count).to eq(1)
    end

    it 'turno novo na mesma conversa pode executar a mesma ação de novo' do
      post_action('iniciar_agendamento', 'msg:902')
      lead.reload.update!(agendamento_status: 'cancelado')

      post_action('iniciar_agendamento', 'msg:903')

      expect(lead.reload.agendamento_status).to eq('em_andamento')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'agendamento_iniciado').count).to eq(2)
    end
  end

  # CP-03 -- P1-021-02: commit da saída estruturada do turno.
  describe 'POST turno (saída estruturada)' do
    def post_turno(turn_id, saida)
      post "/api/v1/accounts/#{account.id}/operational_engine/turno",
           params: { conversation_id: conversation.display_id, turn_id: turn_id, saida: saida }, headers: valid_headers, as: :json
    end

    it 'persiste a saída e o replay do mesmo turno não reaplica nem duplica eventos' do
      saida = { dados_extraidos: { dor_oportunidade: 'fila' }, decisao_qualificacao: 'qualificado', ultimo_ponto: 'CEP' }

      2.times { post_turno('msg:950', saida) }

      expect(response).to have_http_status(:ok)
      expect(lead.reload).to have_attributes(dor_oportunidade: 'fila', qualificacao_status: 'qualificado', ultimo_ponto: 'CEP')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'lead_qualificado').count).to eq(1)
    end
  end
end
