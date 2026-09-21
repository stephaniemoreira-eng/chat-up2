# Recebe IDs de resultados persistidos de uma busca de prospeccao (Sales::ProspectingResult) e
# grava cada um como Contact (sem duplicar, reaproveita DataImport::ContactManager). O card
# Sales::Lead só nasce depois de o Operational Engine persistir o estado no Supabase, sempre no
# pipeline canônico de Prospecção. Não recebe pipeline ou etapa da tela, pois esses campos não
# governam estado operacional.
#
# Alem disso, cada lead criado aqui entra no Operational Engine em Backlog, via
# OperationalEngine::ProspectingImporter -- e a unica fonte outbound ligada ao Engine hoje
# (SSOT MVP01 §10.1). Sem isso o lead existe no Kanban e nao existe pro funil operacional.
class Sales::Prospecting::CreateLeadsFromResultsService
  def initialize(account:, result_ids:, auto_contact_enabled: false, contact_tag: nil)
    @account = account
    @results = account.sales_prospecting_results.where(id: result_ids)
    @auto_contact_enabled = auto_contact_enabled
    @contact_tag = contact_tag.presence
  end

  def perform
    @results.map { |result| create_lead(result) }.compact
  end

  private

  attr_reader :account, :auto_contact_enabled, :contact_tag

  def create_lead(result)
    contact = build_contact(result)
    return nil unless persist_contact(contact, result)
    contact.add_labels(contact_tag) if contact_tag

    engine_lead = import_into_engine(result, contact)
    return nil if engine_lead.nil?

    lead = OperationalEngine::SalesProjectionSync.call(engine_lead)
    lead.update!(
      source: 'operational_engine',
      additional_attributes: lead.additional_attributes.merge(prospecting_attributes(result))
    )
    result.update!(lead: lead)
    Sales::Prospecting::ScanResultJob.perform_later(result.id) if account.feature_enabled?('sales_scan')
    lead
  end

  def persist_contact(contact, result)
    contact.save!
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[Prospecting] Failed to create lead for #{result.name}: #{e.message}"
    nil
  end

  # Falhas no Engine ou na projeção precisam voltar ao chamador: deixar o card persistir sozinho
  # criava duas fontes de verdade. O registro idempotente permite tentar novamente sem duplicar.
  def import_into_engine(result, contact)
    OperationalEngine::ProspectingImporter.call(
      result: result,
      contact: contact,
      auto_contact_enabled: auto_contact_enabled,
      contact_tag: contact_tag
    )
  end

  def prospecting_attributes(result)
    {
      place_id: result.place_id,
      address: result.address,
      website: result.website,
      auto_contact_enabled: auto_contact_enabled
    }.compact
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
