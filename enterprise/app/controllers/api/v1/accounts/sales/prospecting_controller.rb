class Api::V1::Accounts::Sales::ProspectingController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Lead) }

  def search
    outcome = Sales::Prospecting::SearchService.perform(account: Current.account, user: Current.user, params: search_params)
    @search = outcome[:search]
    @results = outcome[:results]
  rescue Sales::Prospecting::GooglePlacesSearchService::MissingApiKeyError
    render json: { error: 'Google Places API key is not configured' }, status: :unprocessable_entity
  end

  def create_leads
    @leads = Sales::Prospecting::CreateLeadsFromResultsService.new(
      account: Current.account,
      pipeline_id: params.require(:pipeline_id),
      sales_stage_id: params[:sales_stage_id],
      result_ids: params.require(:result_ids)
    ).perform
  end

  private

  def search_params
    params.permit(:business_type, :neighborhood, :city, :state, :desired_count, :min_rating, :min_reviews,
                   :require_phone, :require_website, :exclude_keywords, :notes)
  end
end
