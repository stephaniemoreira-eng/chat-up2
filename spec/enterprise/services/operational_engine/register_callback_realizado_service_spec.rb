require 'rails_helper'

RSpec.describe OperationalEngine::RegisterCallbackRealizadoService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      # CP-04 (P2-018-01): callback registrado completo -- Prospect Qualificado + oportunidade (§16.2).
      **pending_callback_attributes
    }.merge(overrides))
  end

  # O serviço também sincroniza SalesProjectionSync (etapa_prospect tem default 'backlog', então
  # sempre existe um card Prospect também) -- sem escopar pelo pipeline Comercial, find_by(
  # operational_lead_id:) é ambíguo entre os dois cards do mesmo lead.
  def comercial_sales_lead(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  it 'marca o callback como realizado e grava o timestamp' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 42)

    expect(lead.reload.agendamento_status).to eq('callback_realizado')
    expect(lead.callback_realizado_em).to be_present
  end

  it 'registra o evento callback_realizado com source human' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 42)

    event = lead.events.find_by(event_type: 'callback_realizado')
    expect(event.source).to eq('human')
    expect(event.metadata['responsavel_atual_id']).to eq(42)
  end

  it 'levanta InvalidTransitionError quando nao ha callback pendente' do
    lead = build_lead(agendamento_status: 'nao_iniciado')

    expect { described_class.call!(lead: lead, user_id: 42) }
      .to raise_error(described_class::InvalidTransitionError)
    expect(lead.reload.agendamento_status).to eq('nao_iniciado')
  end

  it 'a tag CALLBACK some do Kanban Comercial depois de realizado (§16.3)' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 42)

    sales_lead = comercial_sales_lead(lead)
    expect(sales_lead.custom_attributes['engine_tags']).not_to include('callback')
  end

  # CP-04 -- P1-025-01 (SSOT §16.5, §28.17, §28.18).
  describe 'conversão Prospect' do
    let(:lead) { build_lead }

    it 'callback realizado como primeiro marco preenche conversao_em (= callback_realizado_em) e tipo callback' do
      described_class.call!(lead: lead, user_id: 1)

      lead.reload
      expect(lead.conversao_em).to eq(lead.callback_realizado_em)
      expect(lead.tipo_conversao).to eq('callback')
    end

    it 'reunião anterior já converteu: preserva a conversão e ainda registra o callback realizado' do
      original = 3.days.ago.change(usec: 0)
      lead.update!(conversao_em: original, tipo_conversao: 'agendamento')

      described_class.call!(lead: lead, user_id: 1)

      lead.reload
      expect(lead.conversao_em).to eq(original)
      expect(lead.tipo_conversao).to eq('agendamento')
      expect(lead.callback_realizado_em).to be_present
    end

    it 'reprocessamento não duplica o evento nem mexe no primeiro marco' do
      described_class.call!(lead: lead, user_id: 1)
      marco = lead.reload.conversao_em

      expect { described_class.call!(lead: lead, user_id: 1) }.to raise_error(described_class::InvalidTransitionError)
      expect(lead.reload.conversao_em).to eq(marco)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'callback_realizado').count).to eq(1)
    end
  end
end
