# CP-11 (P1-VAL-08; SSOT §22): Dashboard Prospect por coorte. Calcula sobre o Engine (Supabase),
# isolado por conta (`conta_id` = account.id) -- os cards Sales::Lead são projeção (§4) e não
# entram aqui. Toda a regra mora em OperationalEngine::ProspectDashboardMetrics; este controller só
# traduz os filtros oficiais (§22.3) e resolve o nome das inboxes para os seletores.
class Api::V1::Accounts::Sales::ProspectDashboardController < Api::V1::Accounts::Sales::BaseController
  FILTROS_OFICIAIS = %i[data_inicial data_final modo origem_lead segmento inbox_entrada_id].freeze

  before_action -> { authorize(Sales::Lead, :prospect_dashboard?) }

  rescue_from OperationalEngine::ProspectDashboardMetrics::InvalidFilterError do |exception|
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def show
    render json: OperationalEngine::ProspectDashboardMetrics.call(conta_id: Current.account.id, filtros: filtros).merge(
      opcoes_filtro: opcoes_filtro
    )
  end

  private

  # Sem período explícito, a coorte padrão é o mês corrente em America/Sao_Paulo.
  def filtros
    hoje = Time.current.in_time_zone(OperationalEngine::ProspectDashboardMetrics::TIMEZONE).to_date
    params.permit(*FILTROS_OFICIAIS).to_h.symbolize_keys.reverse_merge(
      data_inicial: hoje.beginning_of_month.iso8601, data_final: hoje.end_of_month.iso8601
    )
  end

  def opcoes_filtro
    opcoes = OperationalEngine::ProspectDashboardMetrics.filter_options(conta_id: Current.account.id)
    nomes = Current.account.inboxes.where(id: opcoes[:inbox_entrada_ids]).pluck(:id, :name).to_h
    opcoes.except(:inbox_entrada_ids).merge(
      inboxes_entrada: opcoes[:inbox_entrada_ids].map { |id| { id: id, nome: nomes[id] } }
    )
  end
end
