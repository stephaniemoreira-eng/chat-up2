class Api::V1::Accounts::Sales::StagesController < Api::V1::Accounts::BaseController
  before_action :ensure_sales_pipeline_enabled!
  before_action -> { check_authorization(Sales::Stage) }
  before_action :set_pipeline
  before_action :set_stage, only: [:show, :update, :destroy]

  def index
    @stages = @pipeline.stages
  end

  def show; end

  def create
    @stage = @pipeline.stages.create!(stage_params)
  end

  def update
    @stage.update!(stage_params)
  end

  def destroy
    @stage.destroy!
    head :ok
  end

  def reorder
    Sales::Stage.update_positions(pipeline: @pipeline, positions_hash: params[:positions_hash])
    head :ok
  end

  private

  def ensure_sales_pipeline_enabled!
    return if Current.account.feature_enabled?('sales_pipeline')

    render json: { error: 'Sales pipelines are not enabled for this account' }, status: :forbidden
  end

  def set_pipeline
    @pipeline = Current.account.sales_pipelines.find(params[:pipeline_id])
  end

  def set_stage
    @stage = @pipeline.stages.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:name, :color, :probability, :category, :stale_after_hours)
  end
end
