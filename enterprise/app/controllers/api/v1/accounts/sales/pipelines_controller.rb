class Api::V1::Accounts::Sales::PipelinesController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Pipeline) }
  before_action :set_pipeline, only: [:show, :update, :destroy]

  def index
    @pipelines = Current.account.sales_pipelines.ordered
  end

  def show; end

  def create
    @pipeline = Current.account.sales_pipelines.create!(pipeline_params)
  end

  def update
    @pipeline.update!(pipeline_params)
  end

  def destroy
    @pipeline.destroy!
    head :ok
  end

  def reorder
    Sales::Pipeline.update_positions(account: Current.account, positions_hash: params[:positions_hash])
    head :ok
  end

  private

  def set_pipeline
    @pipeline = Current.account.sales_pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :description, :active, :is_default)
  end
end
