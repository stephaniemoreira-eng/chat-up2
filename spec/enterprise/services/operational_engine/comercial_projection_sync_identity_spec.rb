require 'rails_helper'

# CP-05 -- revalidação ponta a ponta do P1-023-02 (correção observada em D-025): a projeção
# Comercial resolve deterministicamente o lead operacional certo (SSOT §3.4, §5.1, §5.3, §28.39).
# Fluxo real: handoff pela Lavínia → movimentação Comercial → Ganho, com um card manual do mesmo
# contato no mesmo pipeline Comercial criado no meio do caminho.
RSpec.describe OperationalEngine::ComercialProjectionSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991110040') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
                                    etapa_prospect: 'qualificado', qualificacao_status: 'qualificado')
  end
  let(:comercial_pipeline) { Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform }

  def cards_of(engine_lead)
    Sales::Lead.joins(:pipeline).where(operational_lead_id: engine_lead.lead_id)
  end

  def handoff!
    OperationalEngine::Tools::HandoffToCommercialService.new(
      account: account, conversation_id: conversation.display_id, motivo_handoff: 'avanco_comercial'
    ).call
  end

  it 'Prospect e Comercial coexistem como projeções distintas do mesmo lead_id, uma por pipeline' do
    handoff!

    kinds = cards_of(lead).pluck('sales_pipelines.engine_kind')
    expect(kinds).to contain_exactly('prospect', 'comercial')
    expect(cards_of(lead).distinct.count(:id)).to eq(2)
  end

  it 'um card manual do mesmo contato no pipeline Comercial nunca é escolhido nem alterado pelo Engine' do
    handoff!
    engine_card = cards_of(lead).find_by!(sales_pipelines: { engine_kind: 'comercial' })
    manual_card = create(:sales_lead, account: account, contact: contact, pipeline: comercial_pipeline,
                                      stage: comercial_pipeline.stages.find_by!(engine_stage_key: 'oportunidade'), title: 'Card manual')

    OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: 42)
    OperationalEngine::AdvanceEtapaComercialService.call!(lead: lead, etapa: 'em_acompanhamento', user_id: 42)
    OperationalEngine::RegisterResultadoComercialService.call!(lead: lead, resultado: 'ganho', user_id: 42)

    expect(engine_card.reload.stage.engine_stage_key).to eq('ganho')
    expect(manual_card.reload.stage.engine_stage_key).to eq('oportunidade')
    expect(manual_card.operational_lead_id).to be_nil
  end

  it 'reprojetar (retry/reconciliação) não cria uma segunda projeção do mesmo lead no mesmo pipeline' do
    handoff!

    2.times do
      lead.with_lock { OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'retry') }
      OperationalEngine::ProjectionReconciler.flush(lead)
    end

    expect(cards_of(lead).where(sales_pipeline_id: comercial_pipeline.id).count).to eq(1)
  end

  it 'dois leads operacionais distintos nunca compartilham o mesmo card Comercial' do
    other_contact = create(:contact, account: account, phone_number: '+5513991110041')
    other = OperationalEngine::Lead.create!(conta_id: account.id, telefone: other_contact.phone_number,
                                            upsales_contact_id: other_contact.id, **comercial_opportunity_attributes)
    handoff!
    OperationalEngine::ComercialProjectionSync.call(other)

    expect(cards_of(lead).where(sales_pipeline_id: comercial_pipeline.id).pluck(:id))
      .not_to include(*cards_of(other).where(sales_pipeline_id: comercial_pipeline.id).pluck(:id))
  end
end
