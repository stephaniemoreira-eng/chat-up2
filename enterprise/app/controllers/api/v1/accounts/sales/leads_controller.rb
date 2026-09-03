class Api::V1::Accounts::Sales::LeadsController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Lead) }
  before_action :set_lead, only: [:show, :update, :destroy, :move, :link_conversation, :unlink_conversation, :timeline, :update_summary]

  def index
    @leads = filtered_leads.ordered
  end

  # Indicadores do Dashboard (Up Sales). Ver docs/fork/ADR-0004-up-sales-reskin.md.
  def summary
    leads = Current.account.sales_leads

    render json: {
      leads_count: leads.count,
      deals_won_count: leads.won.count,
      last_search_at: leads.where(source: 'busca_prospeccao').maximum(:created_at)
    }
  end

  def show; end

  def create
    @lead = Sales::Leads::CreateService.new(account: Current.account, params: lead_params).perform
  end

  def update
    @lead.update!(lead_update_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  def move
    stage = @lead.pipeline.stages.find(params.require(:sales_stage_id))
    @lead = Sales::Leads::MoveStageService.new(lead: @lead, stage: stage, position: params[:position], user: Current.user).perform
  end

  def link_conversation
    conversation = Current.account.conversations.find(params.require(:conversation_id))
    Sales::Leads::LinkConversationService.new(lead: @lead, conversation: conversation).perform
  end

  def unlink_conversation
    @lead.lead_conversations.find_by!(conversation_id: params.require(:conversation_id)).destroy!
    head :ok
  end

  def timeline
    @timeline = Sales::Leads::TimelineBuilderService.new(
      lead: @lead,
      before: params[:before].present? ? Time.zone.at(params[:before].to_i) : nil,
      per_page: params[:per_page].presence || Sales::Leads::TimelineBuilderService::DEFAULT_PER_PAGE
    ).perform
  end

  def update_summary
    @lead = Sales::Leads::UpdateSummaryService.new(lead: @lead, summary: params.require(:summary), user: Current.user).perform
  end

  private

  def filtered_leads
    leads = Current.account.sales_leads.includes(:prospecting_result)
    leads = leads.where(sales_pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    leads = leads.where(sales_stage_id: params[:stage_id]) if params[:stage_id].present?
    leads = leads.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    leads = leads.joins(:lead_conversations).where(sales_lead_conversations: { conversation_id: params[:conversation_id] }) if params[:conversation_id].present?
    leads
  end

  def set_lead
    @lead = Current.account.sales_leads.find(params[:id])
  end

  def lead_params
    params.require(:lead).permit(:contact_id, :pipeline_id, :sales_stage_id, *shared_lead_attributes)
  end

  def lead_update_params
    params.require(:lead).permit(*shared_lead_attributes)
  end

  def shared_lead_attributes
    [:title, :source, :value, :probability, :expected_close_date, :assignee_id, :notes,
     { custom_attributes: {}, additional_attributes: {} }]
  end
end
