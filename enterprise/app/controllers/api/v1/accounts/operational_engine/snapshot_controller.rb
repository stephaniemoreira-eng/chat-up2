# S-4 (plano do Marco 1): o lado Rails do que docs/agent-runtime-v1.md (up2-agents) pede --
# `GET /operational_engine/health` e o Snapshot (§12.3) via `leadSnapshotSchema`. Sem isso,
# `resolveEngineReadiness()` no up2-agents devolve sempre `engine_api_unavailable` e o modo agent
# em produção fica bloqueado (docs/agent-runtime-v1.md §Pendências).
#
# `::OperationalEngine::*` com `::` explícito: mesmo motivo do ToolsController (colisão de nome
# entre o namespace da rota `Api::V1::Accounts::OperationalEngine` e o módulo de domínio raiz).
class Api::V1::Accounts::OperationalEngine::SnapshotController < Api::V1::Accounts::BaseController
  include ::Concerns::OperationalEngine::ToolAuthentication

  class InvalidTurn < StandardError; end

  # Vira uma checagem real (não uma constante fixa) do lado up2-agents assim que este endpoint
  # existir: autenticação já provou que a conta e a chave são válidas; falta só provar que o
  # Supabase está alcançável, não só o Rails.
  def health
    ::OperationalEngine::Lead.connection.execute('SELECT 1')
    render json: { ok: true }, status: :ok
  rescue StandardError => e
    render_tool_error("operational_engine indisponível: #{e.message}", status: :service_unavailable)
  end

  # CP-03: o turno informa o disparador -- `message_id` (a mensagem que disparou o turno),
  # `contexto_execucao` (conversa|primeiro_contato|recuperacao|agenda) e, no primeiro contato,
  # `activation_id` (a autorização gravada pelo Dispatcher na conversa, CP-01). Tudo é validado
  # contra a conversa/lead: mensagem de outra conversa, contexto desconhecido ou primeiro contato sem
  # ativação válida são recusados (422) -- o up2-agents cai em local_fallback e, em produção, não
  # fala (fail-closed).
  def show
    lead = ::OperationalEngine::Tools::ResolveLeadFromConversation.call(
      account: Current.account,
      conversation_id: params[:conversation_id]
    )

    render json: { ok: true, snapshot: ::OperationalEngine::SnapshotBuilder.call(lead, trigger: turn_trigger(lead)) }, status: :ok
  rescue ::OperationalEngine::Tools::ResolveLeadFromConversation::NotFound, InvalidTurn,
         ::OperationalEngine::TurnMessages::InvalidTrigger => e
    render_tool_error(e.message, status: :unprocessable_entity)
  end

  private

  def turn_trigger(lead)
    contexto = params[:contexto_execucao].presence || ::OperationalEngine::SnapshotBuilder::CONTEXTO_PADRAO
    raise InvalidTurn, 'contexto_execucao inválido' unless ::OperationalEngine::SnapshotBuilder::CONTEXTOS.include?(contexto)

    conversation = ::OperationalEngine::Tools::ResolveLeadFromConversation.conversation(
      account: Current.account, conversation_id: params[:conversation_id]
    )
    validate_first_contact!(conversation, lead) if contexto == 'primeiro_contato'

    { contexto_execucao: contexto }.merge(
      ::OperationalEngine::TurnMessages.call(conversation: conversation, message_id: params[:message_id])
    )
  end

  # Primeiro contato só existe para a ativação que o Dispatcher autorizou nesta conversa e para
  # este lead, e enquanto ela ainda vale -- não é um rótulo que qualquer chamador escolhe.
  def validate_first_contact!(conversation, lead)
    activation = ::OperationalEngine::OriginationActivation.for(conversation)
    valid = activation&.authorized? && activation.lead_id == lead.lead_id &&
            params[:activation_id].present? && activation.activation_id == params[:activation_id]
    raise InvalidTurn, 'ativação de primeiro contato inválida ou já usada' unless valid
    raise InvalidTurn, 'primeiro contato não tem mensagem disparadora' if params[:message_id].present?
  end
end
