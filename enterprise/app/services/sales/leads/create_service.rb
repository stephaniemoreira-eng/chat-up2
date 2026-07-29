class Sales::Leads::CreateService
  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def perform
    contact = @account.contacts.find(@params[:contact_id])
    pipeline = @account.sales_pipelines.find(@params[:pipeline_id])
    stage = @params[:sales_stage_id].present? ? pipeline.stages.find(@params[:sales_stage_id]) : pipeline.stages.ordered.first

    @account.sales_leads.create!(
      lead_attributes.merge(contact: contact, pipeline: pipeline, stage: stage)
    )
  end

  private

  def lead_attributes
    @params.except(:contact_id, :pipeline_id, :sales_stage_id)
  end
end
