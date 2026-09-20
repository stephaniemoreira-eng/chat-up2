require 'rails_helper'

RSpec.describe OperationalEngine::EventWriter do
  let(:lead) { OperationalEngine::Lead.create!(conta_id: 1, telefone: "+551399#{rand(1_000_000..9_999_999)}") }

  def write(**overrides)
    described_class.call({
      lead: lead, event_type: 'lead_criado', source: 'system',
      external_source: 'chatwoot', external_id: 'evt-1', metadata: {}
    }.merge(overrides))
  end

  it 'grava um LeadEvent pro lead' do
    event = write

    expect(event.lead_id).to eq(lead.lead_id)
    expect(event.event_type).to eq('lead_criado')
  end

  it 'inclui o correlation_id gerado nos metadados' do
    event = write

    expect(event.metadata['correlation_id']).to be_present
  end

  it 'preserva os metadados passados junto com o correlation_id' do
    event = write(metadata: { motivo: 'teste' })

    expect(event.metadata['motivo']).to eq('teste')
  end

  it 'nao duplica o evento pro mesmo external_id (teste 28.9)' do
    write
    write

    expect(OperationalEngine::LeadEvent.where(lead: lead).count).to eq(1)
  end

  it 'grava eventos separados pra external_ids diferentes' do
    write(external_id: 'evt-1')
    write(external_id: 'evt-2')

    expect(OperationalEngine::LeadEvent.where(lead: lead).count).to eq(2)
  end
end
