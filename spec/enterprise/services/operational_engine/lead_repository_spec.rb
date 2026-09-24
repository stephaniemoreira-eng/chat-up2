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

  describe '.find_by_telefone' do
    it 'nao cria nada quando o lead nao existe' do
      expect(described_class.find_by_telefone(conta_id: 1, telefone: '+5513991234567')).to be_nil
      expect(OperationalEngine::Lead.count).to eq(0)
    end

    it 'acha um lead existente mesmo com o telefone de busca em formato bruto/nao normalizado' do
      lead = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')

      found = described_class.find_by_telefone(conta_id: 1, telefone: '+55 (13) 99123-4567')

      expect(found&.lead_id).to eq(lead.lead_id)
    end
  end

  # CP-02 -- RISK-019-02 (confirmado no IP-01): nono dígito brasileiro.
  describe 'celular brasileiro com e sem o nono dígito' do
    it 'acha o lead original quando o contato foi reescrito para a forma sem o nono dígito' do
      lead = described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')

      expect(described_class.find_by_telefone(conta_id: 1, telefone: '+551391234567')).to eq(lead)
    end

    it 'não cria um lead duplicado a partir da forma equivalente' do
      described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+5513991234567')

      expect { described_class.find_or_create_by_telefone(conta_id: 1, telefone: '+551391234567') }
        .not_to change(OperationalEngine::Lead, :count)
    end

    it 'a forma exata tem precedência quando as duas já existem' do
      com_nove = OperationalEngine::Lead.create!(conta_id: 1, telefone: '+5513991234567')
      sem_nove = OperationalEngine::Lead.create!(conta_id: 1, telefone: '+551391234567')

      expect(described_class.find_by_telefone(conta_id: 1, telefone: '+551391234567')).to eq(sem_nove)
      expect(described_class.find_by_telefone(conta_id: 1, telefone: '+5513991234567')).to eq(com_nove)
    end

    it 'fixo (começa com 2-5) não vira celular equivalente' do
      OperationalEngine::Lead.create!(conta_id: 1, telefone: '+551332345678')

      expect(described_class.find_by_telefone(conta_id: 1, telefone: '+5513932345678')).to be_nil
    end
  end
end
