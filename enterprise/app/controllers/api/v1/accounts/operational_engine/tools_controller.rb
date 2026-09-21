# S-5 (plano do Marco 1, Contrato B): endpoints que a Lavínia (via up2-agents) chama para agir
# sobre o Engine. Chamador é servidor-a-servidor, nunca uma sessão de navegador -- por isso não
# herda a cadeia de autenticação de Api::V1::Accounts::BaseController (Devise / api_access_token
# de User|AgentBot), que não modela esse caso. `Current.user` fica de propósito sem valor: quem
# age aqui é o sistema em nome da Lavínia, não uma pessoa -- mesma convenção de `user: nil` já
# usada em Sales::Leads::MoveStageService/ComercialProjectionSync para transições que só o
# sistema pode fazer.
#
# `::OperationalEngine::Tools::*` com `::` explícito nas actions abaixo: este controller mora sob
# o namespace `Api::V1::Accounts::OperationalEngine` (o path da rota), que colide de nome com o
# módulo `OperationalEngine` de verdade (raiz, `enterprise/app/models/operational_engine/`) --
# sem o `::`, uma referência futura que dependa de nesting lexical (ex. um `module` aninhado em
# vez de `class A::B::C`) resolveria pro namespace errado.
class Api::V1::Accounts::OperationalEngine::ToolsController < Api::V1::Accounts::BaseController
  skip_before_action :authenticate_user!
  skip_before_action :current_account
  skip_before_action :validate_token_api_access
  before_action :authenticate_engine_tool!

  def schedule_meeting
    result = ::OperationalEngine::Tools::ScheduleMeetingService.new(
      account: Current.account,
      conversation_id: params[:conversation_id],
      summary: params[:summary],
      starts_at: params[:start],
      ends_at: params[:end],
      description: params[:description]
    ).call

    render_tool_result(result, ok_payload: ->(r) { { event_id: r[:event_id] } })
  end

  def update_meeting
    result = ::OperationalEngine::Tools::UpdateMeetingService.new(
      account: Current.account,
      conversation_id: params[:conversation_id],
      event_id: params[:event_id],
      summary: params[:summary],
      starts_at: params[:start],
      ends_at: params[:end],
      description: params[:description]
    ).call

    render_tool_result(result, ok_payload: ->(r) { { event_id: r[:event_id] } })
  end

  def cancel_meeting
    result = ::OperationalEngine::Tools::CancelMeetingService.new(
      account: Current.account,
      conversation_id: params[:conversation_id],
      event_id: params[:event_id]
    ).call

    render_tool_result(result)
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

  def authenticate_engine_tool!
    account = Account.find_by(id: params[:account_id])
    return render_tool_error('conta não encontrada', status: :not_found) if account.blank?

    tenant = account.up_sales_agent_tenant
    provided = request.headers['Authorization'].to_s.delete_prefix('Bearer ').presence

    unless tenant&.engine_api_key.present? && provided.present? &&
           ActiveSupport::SecurityUtils.secure_compare(provided, tenant.engine_api_key)
      return render_tool_error('chave inválida', status: :unauthorized)
    end

    Current.account = account
    # switch_locale_using_account_locale (herdado) lê @current_account direto, não o método
    # current_account que pulamos acima -- sem isso, cairia no locale default em vez do da conta.
    @current_account = account
  end

  def render_tool_result(result, ok_payload: ->(_r) { {} })
    if result[:ok]
      render json: { ok: true, **ok_payload.call(result) }, status: :ok
    else
      render_tool_error(result[:reason], status: :unprocessable_entity)
    end
  end

  def render_tool_error(reason, status:)
    render json: { ok: false, reason: reason }, status: status
  end
end
