class Api::V1::Accounts::Sales::FollowUpController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Lead) }

  def show; end

  def update
    Current.account.update!(follow_up_params)
    render :show
  end

  def sync
    @result = Sales::FollowUp::SyncService.perform(account: Current.account)
  rescue Sales::FollowUp::SyncService::NotConfiguredError
    render json: { error: 'Configure o Kanban e o time de vendedores do Follow-up antes de distribuir.' }, status: :unprocessable_entity
  end

  private

  def follow_up_params
    params.require(:follow_up).permit(:follow_up_pipeline_id, :follow_up_team_id, :follow_up_label)
  end
end
