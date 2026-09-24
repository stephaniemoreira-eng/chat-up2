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

  # CP-02 -- P1-024-04 (§10.2) e P1-024-02 (§10.3).
  describe 'elegibilidade completa e fila real' do
    it 'exclui telefone que não está normalizado em E.164' do
      invalido = build_lead
      invalido.update_column(:telefone, '13 99123-4567') # rubocop:disable Rails/SkipsModelValidations

      expect(proximos.to_a).not_to include(invalido)
    end

    it 'exclui lead que já tem primeira abordagem confirmada no ciclo' do
      ja_abordado = build_lead(primeiro_contato_em: 1.day.ago)

      expect(proximos.to_a).not_to include(ja_abordado)
    end

    it 'candidatos seguem FIFO estrito com desempate estável, independente da ordem das PKs' do
      mesmo_instante = 4.hours.ago
      novo = build_lead(etapa_entrou_em: 1.hour.ago)
      antigo_b = build_lead(etapa_entrou_em: mesmo_instante)
      antigo_a = build_lead(etapa_entrou_em: mesmo_instante)
      mais_antigo = build_lead(etapa_entrou_em: 6.hours.ago)

      empatados = [antigo_a, antigo_b].sort_by(&:lead_id)
      expect(described_class.candidatos(conta_id: 1)).to eq([mais_antigo, *empatados, novo])
    end
  end
end
