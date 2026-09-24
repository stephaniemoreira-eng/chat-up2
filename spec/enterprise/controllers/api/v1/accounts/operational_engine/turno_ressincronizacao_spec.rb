require 'rails_helper'

# CP-16B -- P2-VAL-20: POST operational_engine/turno com modo=ressincronizacao (turno silencioso
# pós-devolução) só grava continuidade, com turn_id próprio `devolucao:<id>`.
RSpec.describe 'Api::V1::Accounts::OperationalEngine::Actions (ressincronização)', type: :request do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa',
                                    ultimo_ponto: 'aguardando_volume')
  end
  let(:headers) { { 'Authorization' => "Bearer #{agent_tenant.issued_engine_api_key}" } }
  let(:path) { "/api/v1/accounts/#{account.id}/operational_engine/turno" }

  def commit(saida, modo: 'ressincronizacao', turn_id: 'devolucao:dev-1')
    post path, params: { conversation_id: conversation.display_id, turn_id: turn_id, modo: modo, saida: saida }, headers: headers, as: :json
    response.parsed_body
  end

  it 'grava o ultimo_ponto novo e ignora decisão/ação/aguardando da saída' do
    body = commit({ ultimo_ponto: 'aguardando_escolha_horario', decisao_qualificacao: 'nao_qualificado',
                    aguardando_resposta: true, acao_sugerida: 'encerrar_nao_qualificado' })

    expect(body['ok']).to be(true)
    expect(lead.reload).to have_attributes(ultimo_ponto: 'aguardando_escolha_horario', lead_status: 'ativo', aguardando_resposta: false)
  end

  it 'é idempotente pelo turn_id da devolução' do
    commit({ ultimo_ponto: 'aguardando_escolha_horario' })
    body = commit({ ultimo_ponto: 'outro_ponto' })

    expect(body['ok']).to be(true)
    expect(lead.reload.ultimo_ponto).to eq('aguardando_escolha_horario')
  end
end
