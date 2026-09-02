# Chama a Google Places API (New) Place Details para os campos que a Text Search (usada na busca
# manual, ver GooglePlacesSearchService) nao traz: business status, categoria e horarios --
# necessarios pro pilar Google/Maps do SCAN v1. Mesma chave (GOOGLE_PLACES_API_KEY).
class Sales::Prospecting::PlaceDetailsService
  ENDPOINT = 'https://places.googleapis.com/v1/places'.freeze
  FIELD_MASK = 'businessStatus,primaryType,regularOpeningHours,websiteUri,nationalPhoneNumber,' \
               'rating,userRatingCount'.freeze
  TIMEOUT_SECONDS = 15

  def self.call(place_id)
    new(place_id).call
  end

  def initialize(place_id)
    @place_id = place_id
  end

  # Retorna nil se a chamada falhar (inclui "lugar nao encontrado mais", ex. place_id invalidado)
  # -- o pilar Maps trata isso como alerta, nao erro fatal.
  def call
    return nil if @place_id.blank? || api_key.blank?

    response = HTTParty.get(
      "#{ENDPOINT}/#{@place_id}",
      headers: { 'X-Goog-Api-Key' => api_key, 'X-Goog-FieldMask' => FIELD_MASK },
      timeout: TIMEOUT_SECONDS
    )
    return nil unless response.success?

    data = response.parsed_response
    {
      business_status: data['businessStatus'],
      primary_type: data['primaryType'],
      has_opening_hours: data['regularOpeningHours'].present?,
      has_website: data['websiteUri'].present?,
      has_phone: data['nationalPhoneNumber'].present?,
      rating: data['rating'],
      user_ratings_total: data['userRatingCount']
    }
  rescue StandardError => e
    Rails.logger.error("[Sales::Prospecting::PlaceDetailsService] #{@place_id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def api_key
    GlobalConfigService.load('GOOGLE_PLACES_API_KEY', '')
  end
end
