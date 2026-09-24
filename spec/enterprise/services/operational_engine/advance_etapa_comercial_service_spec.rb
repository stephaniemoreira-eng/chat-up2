require 'rails_helper'

# CP-05 (P1-023-03, P1-025-02; SSOT §4, §8.4, §21.2).
RSpec.describe OperationalEngine::AdvanceEtapaComercialService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      **comercial_opportunity_attributes
    }.merge(overrides))
  end

  def comercial_card(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  it 'Oportunidade → Em acompanhamento: o Engine persiste etapa + evento e só então o card muda' do
    lead = build_lead
    OperationalEngine::ComercialProjectionSync.call(lead)

    described_class.call!(lead: lead, etapa: 'em_acompanhamento', user_id: 5)

    expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
    event = lead.events.find_by!(event_type: 'etapa_alterada')
    expect(event.metadata).to include('funil' => 'comercial', 'de' => 'oportunidade', 'para' => 'em_acompanhamento')
    expect(comercial_card(lead).stage.engine_stage_key).to eq('em_acompanhamento')
  end

  it 'pedir a etapa atual é no-op, sem evento duplicado' do
    lead = build_lead(etapa_comercial: 'em_acompanhamento')

    expect { described_class.call!(lead: lead, etapa: 'em_acompanhamento', user_id: 5) }.not_to(change { lead.events.count })
  end

  it 'recusa Ganho/Perdido por movimentação -- resultado tem ação própria' do
    lead = build_lead(etapa_comercial: 'em_acompanhamento')

    expect { described_class.call!(lead: lead, etapa: 'ganho', user_id: 5) }
      .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
    expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
    expect(lead.resultado_comercial).to eq('em_aberto')
  end

  it 'recusa voltar etapa (Em acompanhamento → Oportunidade não existe no §8.4)' do
    lead = build_lead(etapa_comercial: 'em_acompanhamento')

    expect { described_class.call!(lead: lead, etapa: 'oportunidade', user_id: 5) }
      .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
  end

  it 'recusa um lead sem oportunidade Comercial' do
    lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110004', upsales_contact_id: contact.id)

    expect { described_class.call!(lead: lead, etapa: 'em_acompanhamento', user_id: 5) }
      .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
    expect(lead.reload.etapa_comercial).to be_nil
  end
end
