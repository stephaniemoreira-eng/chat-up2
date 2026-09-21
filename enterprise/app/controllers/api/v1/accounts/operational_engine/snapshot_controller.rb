# S-4 (plano do Marco 1): o lado Rails do que docs/agent-runtime-v1.md (up2-agents) pede --
# `GET /operational_engine/health` e o Snapshot (§12.3) via `leadSnapshotSchema`. Sem isso,
# `resolveEngineReadiness()` no up2-agents devolve sempre `engine_api_unavailable` e o modo agent
# em produção fica bloqueado (docs/agent-runtime-v1.md §Pendências).
#
# `::OperationalEngine::*` com `::` explícito: mesmo motivo do ToolsController (colisão de nome
# entre o namespace da rota `Api::V1::Accounts::OperationalEngine` e o módulo de domínio raiz).
class Api::V1::Accounts::OperationalEngine::SnapshotController < Api::V1::Accounts::BaseController
  include ::Concerns::OperationalEngine::ToolAuthentication

  # Vira uma checagem real (não uma constante fixa) do lado up2-agents assim que este endpoint
  # existir: autenticação já provou que a conta e a chave são válidas; falta só provar que o
  # Supabase está alcançável, não só o Rails.
  def health
    ::OperationalEngine::Lead.connection.execute('SELECT 1')
    render json: { ok: true }, status: :ok
  rescue StandardError => e
    render_tool_error("operational_engine indisponível: #{e.message}", status: :service_unavailable)
  end

  def show
    lead = ::OperationalEngine::Tools::ResolveLeadFromConversation.call(
      account: Current.account,
      conversation_id: params[:conversation_id]
    )

    render json: { ok: true, snapshot: ::OperationalEngine::SnapshotBuilder.call(lead) }, status: :ok
  rescue ::OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
    render_tool_error(e.message, status: :unprocessable_entity)
  end
end
