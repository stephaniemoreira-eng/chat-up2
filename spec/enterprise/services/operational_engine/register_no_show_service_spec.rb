require 'rails_helper'

RSpec.describe OperationalEngine::RegisterNoShowService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  # CP-05 (P2-025-01): oportunidade Comercial completa, não etapa_comercial solta.
  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      **comercial_opportunity_attributes(etapa_comercial: 'em_acompanhamento')
    }.merge(overrides))
  end

  # O lead tem card nos dois pipelines (Prospect e Comercial) -- escopar pelo Comercial.
  def comercial_sales_lead(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  it 'grava no_show_em e o evento reuniao_no_show, source human' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 7)

    expect(lead.reload.no_show_em).to be_present
    event = lead.events.find_by(event_type: 'reuniao_no_show')
    expect(event.source).to eq('human')
  end

  it 'nao muda etapa_comercial, etapa_prospect nem marca perda automaticamente (§20.3, §28.28)' do
    lead = build_lead(**confirmed_meeting_attributes)

    described_class.call!(lead: lead, user_id: 7)

    expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
    expect(lead.etapa_prospect).to eq('agendado')
    expect(lead.resultado_comercial).to eq('em_aberto')
    expect(lead.lead_status).to eq('ativo')
  end

  it 'aplica a tag NO-SHOW na projecao sem mudar a coluna' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 7)

    sales_lead = comercial_sales_lead(lead)
    expect(sales_lead.custom_attributes['engine_tags']).to include('no_show')
    expect(sales_lead.stage.engine_stage_key).to eq('em_acompanhamento')
  end

  it 'permite registrar mais de um no-show ao longo do tempo (reuniao remarcada)' do
    lead = build_lead
    described_class.call!(lead: lead, user_id: 7)
    first_no_show_em = lead.reload.no_show_em

    travel_to(1.day.from_now) { described_class.call!(lead: lead, user_id: 7) }

    expect(lead.reload.no_show_em).to be > first_no_show_em
    expect(lead.events.where(event_type: 'reuniao_no_show').count).to eq(2)
  end

  # CP-05 (P1-025-02): guarda de backend, independente do botão.
  describe 'guardas de contexto Comercial' do
    it 'recusa um lead sem oportunidade Comercial' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110001', upsales_contact_id: contact.id,
                                             etapa_prospect: 'qualificado', qualificacao_status: 'qualificado')

      expect { described_class.call!(lead: lead, user_id: 7) }
        .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
      expect(lead.reload.no_show_em).to be_nil
      expect(lead.events).to be_empty
    end

    it 'recusa uma oportunidade já resolvida' do
      lead = build_lead(etapa_comercial: 'perdido', resultado_comercial: 'perdido', lead_status: 'encerrado')

      expect { described_class.call!(lead: lead, user_id: 7) }
        .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
      expect(lead.reload.no_show_em).to be_nil
    end
  end
end
