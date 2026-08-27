# Busca empresas por texto livre (nicho + regiao) via Google Places API (New) Text Search.
# Chave configuravel pelo Super Admin em InstallationConfig (GOOGLE_PLACES_API_KEY), sem
# precisar de redeploy. Ver docs/fork/ADR-0004-up-sales-reskin.md.
class Sales::Prospecting::GooglePlacesSearchService
  ENDPOINT = 'https://places.googleapis.com/v1/places:searchText'.freeze
  FIELD_MASK = 'places.id,places.displayName,places.formattedAddress,places.nationalPhoneNumber,' \
               'places.internationalPhoneNumber,places.websiteUri'.freeze
  MAX_RESULTS = 20

  class MissingApiKeyError < StandardError; end

  def self.search(query)
    new(query).perform
  end

  def initialize(query)
    @query = query
  end

  def perform
    raise MissingApiKeyError if api_key.blank?

    response = perform_request
    return [] unless response.success?

    format_results(response.parsed_response)
  end

  private

  attr_reader :query

  def perform_request
    HTTParty.post(
      ENDPOINT,
      headers: {
        'Content-Type' => 'application/json',
        'X-Goog-Api-Key' => api_key,
        'X-Goog-FieldMask' => FIELD_MASK
      },
      body: { textQuery: query, maxResultCount: MAX_RESULTS }.to_json
    )
  end

  def format_results(data)
    (data['places'] || []).map do |place|
      {
        place_id: place['id'],
        name: place.dig('displayName', 'text'),
        address: place['formattedAddress'],
        phone_number: place['nationalPhoneNumber'] || place['internationalPhoneNumber'],
        website: place['websiteUri']
      }
    end
  end

  def api_key
    GlobalConfigService.load('GOOGLE_PLACES_API_KEY', '')
  end
end
