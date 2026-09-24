require 'rails_helper'

# CP-05 (P2-025-03; SSOT §20.3 "a tag pode ser removida manualmente após tratamento/remarcação. O
# evento permanece para sempre.", §7.2, §28.39).
RSpec.describe OperationalEngine::RemoveNoShowTagService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:lead) do
    OperationalEngine::Lead.create!(
      conta_id: account.id, telefone: '+5513991110002', upsales_contact_id: contact.id,
      **comercial_opportunity_attributes(etapa_comercial: 'em_acompanhamento')
    )
  end

  def comercial_tags
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id).custom_attributes['engine_tags']
  end

  before { OperationalEngine::RegisterNoShowService.call!(lead: lead, user_id: 7) }

  it 'a tag aparece depois do no-show e some depois da remoção manual' do
    expect(comercial_tags).to include('no_show')

    described_class.call!(lead: lead, user_id: 7)

    expect(lead.reload.no_show_em).to be_nil
    expect(comercial_tags).not_to include('no_show')
  end

  it 'mantém intacto o evento histórico reuniao_no_show e registra a remoção' do
    no_show_event = lead.events.find_by!(event_type: 'reuniao_no_show')

    described_class.call!(lead: lead, user_id: 7)

    expect(lead.events.find_by(event_type: 'reuniao_no_show')).to eq(no_show_event)
    removal = lead.events.find_by!(event_type: 'no_show_tag_removida')
    expect(removal.source).to eq('human')
    expect(removal.metadata).to include('motivo' => 'tratamento_ou_remarcacao', 'responsavel_atual_id' => 7)
  end

  it 'não mexe em etapa nem resultado Comercial' do
    described_class.call!(lead: lead, user_id: 7)

    expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
    expect(lead.resultado_comercial).to eq('em_aberto')
  end

  it 'é idempotente: sem NO-SHOW corrente não grava evento novo' do
    described_class.call!(lead: lead, user_id: 7)

    expect { described_class.call!(lead: lead, user_id: 7) }.not_to(change { lead.events.count })
  end
end
