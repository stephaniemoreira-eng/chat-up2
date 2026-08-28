class Api::V1::Accounts::UpSales::CalendarEventsController < Api::V1::Accounts::BaseController
  def create
    agent_tenant = Current.account.up_sales_agent_tenant
    if agent_tenant.blank?
      render json: { error: 'Conecte o up2-agents para esta conta antes de agendar.' }, status: :unprocessable_entity
      return
    end

    @event = UpSales::Agents::CreateCalendarEventService.new(
      agent_tenant: agent_tenant,
      summary: event_params[:summary],
      starts_at: event_params[:start],
      ends_at: event_params[:end],
      description: event_params[:description]
    ).perform
  rescue UpSales::Agents::CreateCalendarEventService::SyncError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def event_params
    params.require(:event).permit(:summary, :start, :end, :description)
  end
end
