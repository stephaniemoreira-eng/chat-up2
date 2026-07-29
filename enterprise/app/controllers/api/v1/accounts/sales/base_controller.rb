class Api::V1::Accounts::Sales::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_sales_pipeline_enabled!

  rescue_from ActiveRecord::RecordNotDestroyed, with: :render_restrict_error

  private

  def ensure_sales_pipeline_enabled!
    return if Current.account.feature_enabled?('sales_pipeline')

    render json: { error: 'Sales pipelines are not enabled for this account' }, status: :forbidden
  end

  def render_restrict_error(exception)
    render json: { error: exception.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end
end
