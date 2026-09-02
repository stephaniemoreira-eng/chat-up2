# Chama a Google PageSpeed Insights API (v5, runPagespeed) para o pilar Website do SCAN v1.
# Reusa a mesma chave do Google Places se PAGESPEED_API_KEY nao estiver configurada -- os dois
# produtos podem compartilhar o mesmo projeto/chave no Google Cloud. Ver ScanWeights::WEBSITE.
class Sales::Prospecting::PageSpeedService
  ENDPOINT = 'https://www.googleapis.com/pagespeedonline/v5/runPagespeed'.freeze
  CATEGORIES = %w[performance seo best-practices].freeze
  TIMEOUT_SECONDS = 20

  def self.call(website)
    new(website).call
  end

  def initialize(website)
    @website = website
  end

  # Retorna nil (sem levantar) se faltar site/chave ou a chamada falhar -- o pilar Website
  # trata isso como dado_nao_encontrado, nao como erro fatal do scan inteiro.
  def call
    return nil if @website.blank? || api_key.blank?

    response = HTTParty.get(ENDPOINT, query: query, timeout: TIMEOUT_SECONDS)
    return nil unless response.success?

    categories = response.parsed_response.dig('lighthouseResult', 'categories')
    {
      performance_score: score_for(categories, 'performance'),
      seo_score: score_for(categories, 'seo'),
      best_practices_score: score_for(categories, 'best-practices')
    }
  rescue StandardError => e
    Rails.logger.error("[Sales::Prospecting::PageSpeedService] #{@website}: #{e.class}: #{e.message}")
    nil
  end

  private

  def query
    { url: @website, key: api_key, strategy: 'mobile', category: CATEGORIES }
  end

  def score_for(categories, key)
    raw = categories&.dig(key, 'score')
    raw.nil? ? nil : (raw.to_f * 100).round
  end

  def api_key
    GlobalConfigService.load('PAGESPEED_API_KEY', '').presence || GlobalConfigService.load('GOOGLE_PLACES_API_KEY', '')
  end
end
