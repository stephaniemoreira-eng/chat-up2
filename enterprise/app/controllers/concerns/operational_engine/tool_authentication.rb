# Autenticação servidor-a-servidor compartilhada por todos os controllers do Contrato B/S-4/S-5
# (plano do Marco 1): chamador é sempre o runtime da Lavínia no up2-agents, nunca uma sessão de
# navegador. Extraído do ToolsController original (S-5) porque o SnapshotController (S-4) precisa
# da mesma verificação -- duplicar autenticação é o tipo de divergência que não aparece em teste
# isolado.
#
# `Concerns::` no nome, não `OperationalEngine::` puro: `config/application.rb` monta
# eager_load_paths com `Dir["enterprise/app/**"]` (um nível só, não recursivo -- "**" sem "/"
# final não desce mais que isso), então a raiz do Zeitwerk pra este arquivo é
# `enterprise/app/controllers`, e `concerns/` entra como segmento de namespace real -- ao
# contrário do `app/controllers/concerns` do Rails puro, que É colapsado por convenção. Mesmo
# padrão já em uso por `Concerns::Agentable` (enterprise/app/models/concerns/agentable.rb).
module Concerns::OperationalEngine::ToolAuthentication
  extend ActiveSupport::Concern

  included do
    skip_before_action :authenticate_user!
    skip_before_action :current_account
    skip_before_action :validate_token_api_access
    before_action :authenticate_engine_tool!
  end

  private

  def authenticate_engine_tool!
    account = Account.find_by(id: params[:account_id])
    return render_tool_error('conta não encontrada', status: :not_found) if account.blank?

    tenant = account.up_sales_agent_tenant
    provided = request.headers['Authorization'].to_s.delete_prefix('Bearer ').presence

    # CP-12 (P1-VAL-10): compara o SHA-256 do que foi apresentado com o digest guardado.
    return render_tool_error('chave inválida', status: :unauthorized) unless tenant&.engine_api_key_matches?(provided)

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
