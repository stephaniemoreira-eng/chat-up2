require 'rails_helper'

RSpec.describe OperationalEngine::LeadRepository do
  it 'cria um lead novo quando o telefone nao existe pra conta' do
    lead = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')

    expect(lead).to be_persisted
    expect(lead.conta_id).to eq(1)
  end

  it 'normaliza o telefone antes de procurar/gravar' do
    lead = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+55 (13) 99123-4567')

    expect(lead.telefone).to eq('+5513991234567')
  end

  it 'retorna o lead existente em vez de duplicar (teste 28.7/28.8)' do
    first = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')
    second = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')

    expect(second.lead_id).to eq(first.lead_id)
    expect(OperationalEngine::Lead.where(conta_id: 1, telefone: '+5513991234567').count).to eq(1)
  end

  it 'permite o mesmo telefone em contas diferentes' do
    described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')
    other = described_class.find_or_create_by_telefone(conta_id: 2, telefone: '+5513991234567')

    expect(other.conta_id).to eq(2)
  end

  it 'aceita atributos extras na criacao' do
    lead = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567', attributes: { nome: 'Fulano' })

    expect(lead.nome).to eq('Fulano')
  end

  it 'nao sobrescreve atributos de um lead ja existente' do
    described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567', attributes: { nome: 'Original' })
    lead = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567', attributes: { nome: 'Outro' })

    expect(lead.nome).to eq('Original')
  end
end
