require 'rails_helper'

RSpec.describe Sales::Prospecting::ScanWeights do
  describe '.faixa_for' do
    it 'maps the documented ranges to their faixa' do
      expect(described_class.faixa_for(0)).to eq('baixa_prioridade')
      expect(described_class.faixa_for(49)).to eq('baixa_prioridade')
      expect(described_class.faixa_for(50)).to eq('revisao_humana')
      expect(described_class.faixa_for(69)).to eq('revisao_humana')
      expect(described_class.faixa_for(70)).to eq('revisao_prioritaria')
      expect(described_class.faixa_for(100)).to eq('revisao_prioritaria')
    end
  end

  it 'keeps the four pilares summing to 100' do
    expect(described_class::PILARES.values.sum).to eq(100)
  end
end
