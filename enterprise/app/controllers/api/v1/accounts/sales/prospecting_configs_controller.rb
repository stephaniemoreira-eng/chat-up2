# CRUD das buscas automaticas salvas (Sales::ProspectingConfig). Ver Sales::Prospecting::
# RunConfigService e Sales::Prospecting::AutoSearchJob (cron diario que as executa).
class Api::V1::Accounts::Sales::ProspectingConfigsController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Lead) }
  before_action :set_config, only: %i[update destroy]

  def index
    @configs = Current.account.sales_prospecting_configs.order(created_at: :desc)
  end

  def create
    @config = Current.account.sales_prospecting_configs.create!(config_params)
  end

  def update
    @config.update!(config_params)
  end

  def destroy
    @config.destroy!
    head :ok
  end

  private

  def set_config
    @config = Current.account.sales_prospecting_configs.find(params[:id])
  end

  def config_params
    permitted = params.permit(:business_type, :neighborhood, :city, :state, :desired_count, :min_rating,
                               :min_reviews, :require_phone, :require_website, :exclude_keywords, :active,
                               :pipeline_id, :sales_stage_id)
    permitted[:sales_pipeline_id] = permitted.delete(:pipeline_id) if permitted.key?(:pipeline_id)
    permitted
  end
end
