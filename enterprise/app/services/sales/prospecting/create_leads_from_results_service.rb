# Recebe resultados selecionados de uma busca de prospeccao (Google Places) e grava cada um
# como Contact (sem duplicar, reaproveita DataImport::ContactManager) + Sales::Lead com
# source: 'busca_prospeccao'. Ver docs/fork/ADR-0004-up-sales-reskin.md.
class Sales::Prospecting::CreateLeadsFromResultsService
  def initialize(account:, pipeline_id:, sales_stage_id:, results:)
    @account = account
    @pipeline = account.sales_pipelines.find(pipeline_id)
    @stage = sales_stage_id.present? ? @pipeline.stages.find(sales_stage_id) : @pipeline.stages.ordered.first
    @results = results
  end

  def perform
    @results.map { |result| create_lead(result) }.compact
  end

  private

  attr_reader :account, :pipeline, :stage

  def create_lead(result)
    contact = build_contact(result)
    contact.save!

    account.sales_leads.create!(
      contact: contact,
      pipeline: pipeline,
      stage: stage,
      title: result[:name],
      source: 'busca_prospeccao',
      additional_attributes: {
        place_id: result[:place_id],
        address: result[:address],
        website: result[:website]
      }.compact
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[Prospecting] Failed to create lead for #{result[:name]}: #{e.message}"
    nil
  end

  def build_contact(result)
    DataImport::ContactManager.new(account).build_contact(
      name: result[:name],
      phone_number: result[:phone_number],
      company_name: result[:name],
      city: result[:address]
    )
  end
end
