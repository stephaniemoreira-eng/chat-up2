require 'rails_helper'

RSpec.describe OperationalEngine::SetPropensaoService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      etapa_comercial: 'oportunidade'
    }.merge(overrides))
  end

  # O serviço também sincroniza SalesProjectionSync (etapa_prospect tem default 'backlog', então
  # sempre existe um card Prospect também) -- sem escopar pelo pipeline Comercial, find_by(
  # operational_lead_id:) é ambíguo entre os dois cards do mesmo lead.
  def comercial_sales_lead(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  it 'grava a propensao e registra o evento' do
    lead = build_lead

    described_class.call!(lead: lead, propensao: 'quente', user_id: 3)

    expect(lead.reload.propensao_fechamento).to eq('quente')
    event = lead.events.find_by(event_type: 'propensao_atualizada')
    expect(event.metadata['propensao_fechamento']).to eq('quente')
  end

  it 'reflete a tag no Kanban Comercial' do
    lead = build_lead

    described_class.call!(lead: lead, propensao: 'frio', user_id: 3)

    sales_lead = comercial_sales_lead(lead)
    expect(sales_lead.custom_attributes['engine_tags']).to include('frio')
  end

  it 'e idempotente: reclassificar pro mesmo valor nao duplica evento nem re-sincroniza' do
    lead = build_lead(propensao_fechamento: 'morno')

    expect { described_class.call!(lead: lead, propensao: 'morno', user_id: 3) }
      .not_to change { lead.events.count }
  end
end
