# Executa uma busca automatica salva (Sales::ProspectingConfig): roda a mesma busca da tela
# manual (Sales::Prospecting::SearchService) e cria lead pra todo resultado que passar nos
# filtros -- sem selecao manual, ja que ninguem esta olhando a tela quando isso roda sozinho.
#
# Dedup: o mesmo segmento/cidade rodando todo dia vai devolver as mesmas empresas de novo. Sem
# checar isso, cada execucao criaria um Contact/Sales::Lead duplicado pra empresa que ja virou
# lead numa execucao anterior. Pula lead novo pra place_id que a conta ja tem como lead.
class Sales::Prospecting::RunConfigService
  def self.call(config)
    new(config).call
  end

  def initialize(config)
    @config = config
  end

  def call
    outcome = Sales::Prospecting::SearchService.perform(account: @config.account, user: nil, params: search_params)
    new_result_ids = outcome[:results].reject { |result| already_a_lead?(result) }.map(&:id)

    leads = new_result_ids.any? ? create_leads(new_result_ids) : []
    @config.update!(last_run_at: Time.current)
    leads
  end

  private

  def search_params
    {
      business_type: @config.business_type,
      neighborhood: @config.neighborhood,
      city: @config.city,
      state: @config.state,
      desired_count: @config.desired_count,
      min_rating: @config.min_rating,
      min_reviews: @config.min_reviews,
      require_phone: @config.require_phone,
      require_website: @config.require_website,
      exclude_keywords: @config.exclude_keywords
    }
  end

  def already_a_lead?(result)
    @config.account.sales_prospecting_results
           .where(place_id: result.place_id)
           .where.not(id: result.id)
           .where.not(sales_lead_id: nil)
           .exists?
  end

  def create_leads(result_ids)
    Sales::Prospecting::CreateLeadsFromResultsService.new(
      account: @config.account,
      pipeline_id: @config.sales_pipeline_id,
      sales_stage_id: @config.sales_stage_id,
      result_ids: result_ids
    ).perform
  end
end
