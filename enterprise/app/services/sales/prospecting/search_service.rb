# Orquestra uma busca de prospeccao: monta a query textual a partir de segmento + bairro/
# cidade/estado, chama o Google Places, filtra os resultados (nota minima, avaliacoes minimas,
# exigir telefone/site, palavras excluidas) e grava a busca + os resultados filtrados para
# historico (Sales::ProspectingSearch/Sales::ProspectingResult). Ver docs/fork/ADR-0004.
class Sales::Prospecting::SearchService
  DEFAULT_DESIRED_COUNT = 20

  def self.perform(account:, user:, params:)
    new(account: account, user: user, params: params).perform
  end

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params
  end

  def perform
    raw_results = Sales::Prospecting::GooglePlacesSearchService.search(query, max_results: desired_count)
    filtered_results = raw_results.select { |result| passes_filters?(result) }

    search = persist_search
    results = persist_results(search, filtered_results)

    { search: search, results: results }
  end

  private

  attr_reader :account, :user, :params

  def query
    location = [params[:neighborhood], params[:city], params[:state]].reject(&:blank?).join(', ')
    "#{params[:business_type]} em #{location}"
  end

  def desired_count
    params[:desired_count].presence&.to_i || DEFAULT_DESIRED_COUNT
  end

  def min_rating
    params[:min_rating].presence&.to_f
  end

  def min_reviews
    params[:min_reviews].presence&.to_i
  end

  def require_phone?
    ActiveModel::Type::Boolean.new.cast(params[:require_phone])
  end

  def require_website?
    ActiveModel::Type::Boolean.new.cast(params[:require_website])
  end

  def exclude_keyword_list
    params[:exclude_keywords].to_s.split(',').map { |keyword| keyword.strip.downcase }.reject(&:blank?)
  end

  def passes_filters?(result)
    return false if min_rating.present? && (result[:rating] || 0) < min_rating
    return false if min_reviews.present? && (result[:user_ratings_total] || 0) < min_reviews
    return false if require_phone? && result[:phone_number].blank?
    return false if require_website? && result[:website].blank?
    return false if excluded?(result)

    true
  end

  def excluded?(result)
    keywords = exclude_keyword_list
    return false if keywords.empty?

    haystack = "#{result[:name]} #{result[:address]}".downcase
    keywords.any? { |keyword| haystack.include?(keyword) }
  end

  def persist_search
    account.sales_prospecting_searches.create!(
      user: user,
      business_type: params[:business_type],
      neighborhood: params[:neighborhood],
      city: params[:city],
      state: params[:state],
      desired_count: desired_count,
      min_rating: min_rating,
      min_reviews: min_reviews,
      require_phone: require_phone?,
      require_website: require_website?,
      exclude_keywords: params[:exclude_keywords],
      notes: params[:notes]
    )
  end

  def persist_results(search, filtered_results)
    filtered_results.map do |result|
      search.results.create!(
        account: account,
        place_id: result[:place_id],
        name: result[:name],
        address: result[:address],
        phone_number: result[:phone_number],
        website: result[:website],
        rating: result[:rating],
        user_ratings_total: result[:user_ratings_total]
      )
    end
  end
end
