require 'rails_helper'

RSpec.describe OperationalEngine::RegisterNoShowService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      etapa_comercial: 'em_acompanhamento'
    }.merge(overrides))
  end

  it 'grava no_show_em e o evento reuniao_no_show, source human' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 7)

    expect(lead.reload.no_show_em).to be_present
    event = lead.events.find_by(event_type: 'reuniao_no_show')
    expect(event.source).to eq('human')
  end

  it 'nao muda etapa_comercial nem marca perda automaticamente (§20.3)' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 7)

    expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
    expect(lead.resultado_comercial).to eq('em_aberto')
  end

  it 'aplica a tag NO-SHOW na projecao sem mudar a coluna' do
    lead = build_lead

    described_class.call!(lead: lead, user_id: 7)

    sales_lead = Sales::Lead.find_by(operational_lead_id: lead.lead_id)
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
end
