require 'rails_helper'

RSpec.describe OperationalEngine::BacklogSelector do
  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: 1, telefone: "+551399#{rand(1_000_000..9_999_999)}",
      etapa_prospect: 'backlog', lead_status: 'ativo', etapa_entrou_em: Time.current
    }.merge(overrides))
  end

  def proximos(agora_str: '2026-09-21 09:30')
    agora = ActiveSupport::TimeZone['America/Sao_Paulo'].parse(agora_str)
    described_class.proximos(conta_id: 1, agora: agora)
  end

  it 'segue FIFO por etapa_entrou_em (teste §10.3)' do
    mais_novo = build_lead(etapa_entrou_em: 2.hours.ago)
    mais_antigo = build_lead(etapa_entrou_em: 5.hours.ago)
    meio = build_lead(etapa_entrou_em: 3.hours.ago)

    expect(proximos.to_a).to eq([mais_antigo, meio, mais_novo])
  end

  it 'limita ao que a capacidade da janela permite' do
    15.times { build_lead }

    expect(proximos.count).to eq(10) # teto da janela da manha, §10.4
  end

  it 'esta vazio fora do horario operacional, mesmo com Backlog cheio' do
    build_lead

    expect(proximos(agora_str: '2026-09-21 12:00')).to be_empty
  end

  describe 'elegibilidade (§10.2)' do
    it 'exclui lead fora do Backlog' do
      build_lead(etapa_prospect: 'em_conversa')

      expect(proximos).to be_empty
    end

    it 'exclui lead encerrado' do
      build_lead(lead_status: 'encerrado')

      expect(proximos).to be_empty
    end

    it 'exclui lead marcado nao_contatar' do
      build_lead(nao_contatar: true)

      expect(proximos).to be_empty
    end

    it 'exclui lead que e cliente_atual' do
      build_lead(relacao_atual: 'cliente_atual')

      expect(proximos).to be_empty
    end

    it 'inclui lead com relacao_atual em branco -- NULL nao e cliente_atual' do
      lead = build_lead(relacao_atual: nil)

      expect(proximos).to include(lead)
    end

    it 'exclui lead em modo_atendimento humano' do
      build_lead(modo_atendimento: 'humano')

      expect(proximos).to be_empty
    end

    it 'nao mistura leads de contas diferentes' do
      build_lead(conta_id: 2)

      expect(proximos).to be_empty
    end
  end
end
