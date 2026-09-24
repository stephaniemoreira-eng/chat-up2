require 'rails_helper'

RSpec.describe OperationalEngine::SetPropensaoService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  # CP-05 (P2-025-01): oportunidade Comercial completa, não etapa_comercial solta.
  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      **comercial_opportunity_attributes
    }.merge(overrides))
  end

  # O lead tem card nos dois pipelines (Prospect e Comercial) -- escopar pelo Comercial.
  def comercial_sales_lead(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  it 'grava a propensao e registra o evento com de/para' do
    lead = build_lead

    described_class.call!(lead: lead, propensao: 'quente', user_id: 3)

    expect(lead.reload.propensao_fechamento).to eq('quente')
    event = lead.events.find_by(event_type: 'propensao_atualizada')
    expect(event.metadata).to include('propensao_fechamento' => 'quente', 'de' => 'nao_classificado', 'para' => 'quente')
  end

  it 'reflete a tag no Kanban Comercial' do
    lead = build_lead

    described_class.call!(lead: lead, propensao: 'frio', user_id: 3)

    sales_lead = comercial_sales_lead(lead)
    expect(sales_lead.custom_attributes['engine_tags']).to include('frio')
  end

  it 'e idempotente: reclassificar pro mesmo valor nao duplica evento' do
    lead = build_lead(propensao_fechamento: 'morno')

    expect { described_class.call!(lead: lead, propensao: 'morno', user_id: 3) }
      .not_to(change { lead.events.count })
  end

  it 'recusa um valor fora do enum §6.2' do
    lead = build_lead

    expect { described_class.call!(lead: lead, propensao: 'fervendo', user_id: 3) }
      .to raise_error(described_class::InvalidPropensaoError)
  end

  # CP-05 (P1-025-02, §20.2): propensão é classificação do Comercial -- sem oportunidade, não há o
  # que classificar, mesmo por chamada direta.
  describe 'guardas de contexto Comercial' do
    it 'recusa um lead sem oportunidade Comercial' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110003', upsales_contact_id: contact.id)

      expect { described_class.call!(lead: lead, propensao: 'quente', user_id: 3) }
        .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
      expect(lead.reload.propensao_fechamento).to eq('nao_classificado')
      expect(lead.events).to be_empty
    end

    it 'recusa uma oportunidade já ganha' do
      lead = build_lead(etapa_comercial: 'ganho', resultado_comercial: 'ganho', lead_status: 'encerrado')

      expect { described_class.call!(lead: lead, propensao: 'frio', user_id: 3) }
        .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
    end
  end
end
