# Recebe IDs de resultados persistidos de uma busca de prospeccao (Sales::ProspectingResult) e
# grava cada um como Contact (sem duplicar, reaproveita DataImport::ContactManager) + Sales::Lead
# com source: 'busca_prospeccao'. auto_contact_enabled vem da Sales::ProspectingConfig que gerou
# a busca (quando veio de uma) e e gravado em additional_attributes de cada lead -- trava que o
# futuro contato ativo do agente de IA vai checar antes de escrever pro lead. Ver
# docs/fork/ADR-0004-up-sales-reskin.md.
#
# Alem disso, cada lead criado aqui entra no Operational Engine em Backlog, via
# OperationalEngine::ProspectingImporter -- e a unica fonte outbound ligada ao Engine hoje
# (SSOT MVP01 §10.1). Sem isso o lead existe no Kanban e nao existe pro funil operacional.
class Sales::Prospecting::CreateLeadsFromResultsService
  def initialize(account:, pipeline_id:, sales_stage_id:, result_ids:, auto_contact_enabled: false, contact_tag: nil)
    @account = account
    @pipeline = account.sales_pipelines.find(pipeline_id)
    @stage = sales_stage_id.present? ? @pipeline.stages.find(sales_stage_id) : @pipeline.stages.ordered.first
    @results = account.sales_prospecting_results.where(id: result_ids)
    @auto_contact_enabled = auto_contact_enabled
    @contact_tag = contact_tag.presence
  end

  def perform
    @results.map { |result| create_lead(result) }.compact
  end

  private

  attr_reader :account, :pipeline, :stage, :auto_contact_enabled, :contact_tag

  def create_lead(result)
    contact = build_contact(result)
    contact.save!
    contact.add_labels(contact_tag) if contact_tag

    lead = account.sales_leads.create!(
      contact: contact,
      pipeline: pipeline,
      stage: stage,
      title: result.name,
      source: 'busca_prospeccao',
      additional_attributes: {
        place_id: result.place_id,
        address: result.address,
        website: result.website,
        auto_contact_enabled: auto_contact_enabled
      }.compact
    )
    result.update!(lead: lead)
    import_into_engine(result, contact)
    Sales::Prospecting::ScanResultJob.perform_later(result.id) if account.feature_enabled?('sales_scan')
    lead
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[Prospecting] Failed to create lead for #{result.name}: #{e.message}"
    nil
  end

  # O funil de verdade mora no Operational Engine (Supabase); o Kanban acima e projecao. Mas uma
  # falha la -- Supabase fora do ar, instalacao sem OPERATIONAL_ENGINE_DATABASE_URL -- nao pode
  # derrubar a busca, que continua valendo sozinha: contato e card ja existem. Fica o log com o
  # id do resultado, que e o suficiente pra reimportar depois.
  def import_into_engine(result, contact)
    OperationalEngine::ProspectingImporter.call(
      result: result,
      contact: contact,
      auto_contact_enabled: auto_contact_enabled,
      contact_tag: contact_tag
    )
  rescue StandardError => e
    Rails.logger.error "[Prospecting] Operational Engine import failed for result #{result.id}: #{e.class}: #{e.message}"
  end

  def build_contact(result)
    DataImport::ContactManager.new(account).build_contact(
      name: result.name,
      phone_number: result.phone_number,
      company_name: result.name,
      city: result.address
    )
  end
end
