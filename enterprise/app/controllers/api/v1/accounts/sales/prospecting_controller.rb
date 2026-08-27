class Api::V1::Accounts::Sales::ProspectingController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Lead) }

  def search
    @results = Sales::Prospecting::GooglePlacesSearchService.search(search_query)
  rescue Sales::Prospecting::GooglePlacesSearchService::MissingApiKeyError
    render json: { error: 'Google Places API key is not configured' }, status: :unprocessable_entity
  end

  def create_leads
    @leads = Sales::Prospecting::CreateLeadsFromResultsService.new(
      account: Current.account,
      pipeline_id: params.require(:pipeline_id),
      sales_stage_id: params[:sales_stage_id],
      results: results_params
    ).perform
  end

  private

  def search_query
    params.require(:query)
  end

  def results_params
    params.require(:results).map do |result|
      result.permit(:place_id, :name, :address, :phone_number, :website).to_h.symbolize_keys
    end
  end
end
