# S-5 (plano do Marco 1, Contrato B): endpoints que a Lavínia (via up2-agents) chama para agir
# sobre o Engine. Chamador é servidor-a-servidor, nunca uma sessão de navegador -- por isso não
# herda a cadeia de autenticação de Api::V1::Accounts::BaseController (Devise / api_access_token
# de User|AgentBot), que não modela esse caso. `Current.user` fica de propósito sem valor: quem
# age aqui é o sistema em nome da Lavínia, não uma pessoa -- mesma convenção de `user: nil` já
# usada em Sales::Leads::MoveStageService/ComercialProjectionSync para transições que só o
# sistema pode fazer.
#
# `::OperationalEngine::*` com `::` explícito neste arquivo: este controller mora sob o namespace
# `Api::V1::Accounts::OperationalEngine` (o path da rota), que colide de nome com o módulo
# `OperationalEngine` de verdade (raiz, `enterprise/app/models/operational_engine/`) -- sem o
# `::`, uma referência futura que dependa de nesting lexical (ex. um `module` aninhado em vez de
# `class A::B::C`) resolveria pro namespace errado. Autenticação compartilhada com
# SnapshotController (S-4) via `Concerns::OperationalEngine::ToolAuthentication` -- ver o
# comentário nesse arquivo sobre por que o nome carrega o prefixo `Concerns::`.
class Api::V1::Accounts::OperationalEngine::ToolsController < Api::V1::Accounts::BaseController
  include ::Concerns::OperationalEngine::ToolAuthentication

  # CP-10 (P1-VAL-03): schedule/update/cancel são as ferramentas "Criar evento", "Atualizar evento" e
  # "Cancelar evento" da Lavínia no modo agent (Prompt V1.0, FERRAMENTAS) -- chamadas pelo modelo
  # DURANTE o turno, antes de ele redigir a resposta, para que "agendado" só seja dito depois do
  # retorno real (regra 18). Idempotentes pela identidade do turno (`turn_id`, mesmo ledger do
  # ActionsController): repetir a chamada no mesmo turno devolve o resultado guardado sem criar/alterar/
  # cancelar outro evento no Calendar. Sem turn_id (chamador legado) seguem como antes.
  def schedule_meeting
    result = turn_idempotent('ferramenta:criar_evento') do
      ::OperationalEngine::Tools::ScheduleMeetingService.new(
        account: Current.account,
        conversation_id: params[:conversation_id],
        summary: params[:summary],
        starts_at: params[:start],
        ends_at: params[:end],
        description: params[:description]
      ).call
    end

    render_tool_result(result, ok_payload: ->(r) { { event_id: r[:event_id], **r.slice(:ja_existia, :replay) } })
  end

  # `event_id` vem da URL (rota legada) ou não vem (rota do modo agent): sem ele, o Engine usa a
  # reunião confirmada do próprio lead -- o modelo nunca carrega um identificador do Calendar.
  def update_meeting
    result = turn_idempotent('ferramenta:atualizar_evento') do
      ::OperationalEngine::Tools::UpdateMeetingService.new(
        account: Current.account,
        conversation_id: params[:conversation_id],
        event_id: params[:event_id],
        summary: params[:summary],
        starts_at: params[:start],
        ends_at: params[:end],
        description: params[:description]
      ).call
    end

    render_tool_result(result, ok_payload: ->(r) { { event_id: r[:event_id], **r.slice(:replay) } })
  end

  def cancel_meeting
    result = turn_idempotent('ferramenta:cancelar_evento') do
      ::OperationalEngine::Tools::CancelMeetingService.new(
        account: Current.account,
        conversation_id: params[:conversation_id],
        event_id: params[:event_id]
      ).call
    end

    render_tool_result(result, ok_payload: ->(r) { r.slice(:replay) })
  end

  def register_callback
    result = ::OperationalEngine::Tools::RegisterCallbackService.new(
      account: Current.account,
      conversation_id: params[:conversation_id]
    ).call

    render_tool_result(result)
  end

  def availability
    result = ::OperationalEngine::Tools::AvailabilityService.new(
      account: Current.account,
      time_min: params[:time_min],
      time_max: params[:time_max]
    ).call

    render_tool_result(result, ok_payload: ->(r) { { events: r[:events] } })
  end

  private

  def turn_idempotent(operacao, &)
    ::OperationalEngine::TurnIdempotency.call(conta_id: Current.account.id, operacao: operacao, turn_id: params[:turn_id], &)
  end
end
