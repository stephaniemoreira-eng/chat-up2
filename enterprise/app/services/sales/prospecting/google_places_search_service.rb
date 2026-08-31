# Busca empresas por texto livre (segmento + bairro/cidade/estado) via Google Places API (New)
# Text Search. Chave configuravel pelo Super Admin em InstallationConfig (GOOGLE_PLACES_API_KEY),
# sem precisar de redeploy. Ver docs/fork/ADR-0004-up-sales-reskin.md.
#
# Pagina automaticamente ate max_results (tope de MAX_RESULTS, o limite inicial do MVP) usando
# o nextPageToken da API. Um pequeno delay antes de reusar o token evita erros da API do Google
# com o token ainda nao propagado - so acontece quando o resultado pedido exige mais de uma pagina.
class Sales::Prospecting::GooglePlacesSearchService
  ENDPOINT = 'https://places.googleapis.com/v1/places:searchText'.freeze
  FIELD_MASK = 'places.id,places.displayName,places.formattedAddress,places.nationalPhoneNumber,' \
               'places.internationalPhoneNumber,places.websiteUri,places.rating,places.userRatingCount'.freeze
  PAGE_SIZE = 20
  MAX_RESULTS = 60
  PAGE_TOKEN_DELAY_SECONDS = 2

  class MissingApiKeyError < StandardError; end

  def self.search(query, max_results: PAGE_SIZE)
    new(query, max_results).perform
  end

  def initialize(query, max_results)
    @query = query
    @max_results = max_results.to_i.clamp(1, MAX_RESULTS)
  end

  def perform
    raise MissingApiKeyError if api_key.blank?

    results = []
    page_token = nil

    loop do
      response = perform_request(page_token)
      break unless response.success?

      data = response.parsed_response
      results.concat(format_results(data))
      page_token = data['nextPageToken']

      break if results.size >= @max_results || page_token.blank?

      sleep PAGE_TOKEN_DELAY_SECONDS
    end

    results.first(@max_results)
  end

  private

  attr_reader :query

  def perform_request(page_token)
    body = { textQuery: query, maxResultCount: PAGE_SIZE }
    body[:pageToken] = page_token if page_token.present?

    HTTParty.post(
      ENDPOINT,
      headers: {
        'Content-Type' => 'application/json',
        'X-Goog-Api-Key' => api_key,
        'X-Goog-FieldMask' => FIELD_MASK
      },
      body: body.to_json
    )
  end

  def format_results(data)
    (data['places'] || []).map do |place|
      {
        place_id: place['id'],
        name: place.dig('displayName', 'text'),
        address: place['formattedAddress'],
        phone_number: normalized_phone_number(place['internationalPhoneNumber']),
        website: place['websiteUri'],
        rating: place['rating'],
        user_ratings_total: place['userRatingCount']
      }
    end
  end

  # Google returns internationalPhoneNumber as e.g. "+55 13 3222-1234" -- Contact#phone_number
  # requires strict E.164 (no spaces/punctuation). nationalPhoneNumber has no country code at all,
  # so it can't be turned into a valid E.164 number without guessing a country -- drop the phone
  # rather than build one that's silently wrong or that fails Contact validation later.
  def normalized_phone_number(raw)
    return nil if raw.blank?

    digits = raw.gsub(/[^\d+]/, '')
    digits if digits.match?(/\A\+[1-9]\d{1,14}\z/)
  end

  def api_key
    GlobalConfigService.load('GOOGLE_PLACES_API_KEY', '')
  end
end
