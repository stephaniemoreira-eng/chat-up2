require 'rails_helper'

RSpec.describe OperationalEngine::RegisterResultadoComercialService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      etapa_comercial: 'em_acompanhamento'
    }.merge(overrides))
  end

  # O serviço também sincroniza SalesProjectionSync (etapa_prospect tem default 'backlog', então
  # sempre existe um card Prospect também) -- sem escopar pelo pipeline Comercial, find_by(
  # operational_lead_id:) é ambíguo entre os dois cards do mesmo lead.
  def comercial_sales_lead(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  describe 'ganho' do
    it 'grava resultado_comercial, etapa_comercial, ganho_em e relacao_atual (§17.4)' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)
      lead.reload

      expect(lead.resultado_comercial).to eq('ganho')
      expect(lead.etapa_comercial).to eq('ganho')
      expect(lead.ganho_em).to be_present
      expect(lead.relacao_atual).to eq('cliente_atual')
      expect(lead.lead_status).to eq('encerrado')
    end

    it 'move o card pra coluna Ganho' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)

      sales_lead = comercial_sales_lead(lead)
      expect(sales_lead.stage.engine_stage_key).to eq('ganho')
      expect(sales_lead).to be_won
    end

    it 'registra o evento resultado_ganho' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)

      expect(lead.events.find_by(event_type: 'resultado_ganho')).to be_present
    end
  end

  describe 'perdido' do
    it 'grava resultado_comercial, etapa_comercial e motivo_perda opcional' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'perdido', user_id: 9, motivo_perda: 'escolheu concorrente')
      lead.reload

      expect(lead.resultado_comercial).to eq('perdido')
      expect(lead.etapa_comercial).to eq('perdido')
      expect(lead.motivo_perda).to eq('escolheu concorrente')
      expect(lead.lead_status).to eq('encerrado')
      expect(lead.ganho_em).to be_nil
    end

    it 'permite perdido sem motivo_perda (opcional)' do
      lead = build_lead

      expect { described_class.call!(lead: lead, resultado: 'perdido', user_id: 9) }.not_to raise_error
      expect(lead.reload.motivo_perda).to be_nil
    end
  end

  it 'levanta AlreadyResolvedError quando a oportunidade ja foi resolvida' do
    lead = build_lead(resultado_comercial: 'ganho', etapa_comercial: 'ganho')

    expect { described_class.call!(lead: lead, resultado: 'perdido', user_id: 9) }
      .to raise_error(described_class::AlreadyResolvedError)
    expect(lead.reload.resultado_comercial).to eq('ganho')
  end

  it 'levanta InvalidResultadoError pra um valor fora de ganho/perdido' do
    lead = build_lead

    expect { described_class.call!(lead: lead, resultado: 'em_aberto', user_id: 9) }
      .to raise_error(described_class::InvalidResultadoError)
  end
end
