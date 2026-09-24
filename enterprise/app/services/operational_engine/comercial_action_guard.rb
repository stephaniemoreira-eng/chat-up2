# CP-05 (P1-025-02; SSOT §3.2 "regras de transição pertencem ao Operational Engine", §8.4, §17.4,
# §20.2, §20.3, §21.2). Guardas de domínio das ações humanas do Kanban Comercial. Esconder o botão
# no frontend é só UX -- estas guardas valem para qualquer chamada direta/replay por API.
#
# Tem que ser chamada DENTRO do `lead.with_lock` da mutação (estado relido), mesma regra do
# LaviniaActionGuard.
#
# Contexto exigido = oportunidade Comercial aberta: `etapa_comercial` em Oportunidade ou Em
# acompanhamento e `resultado_comercial = em_aberto`. `frente_operacional = comercial` NÃO é
# exigido de propósito: o próprio SSOT cria a oportunidade sem handoff na reunião confirmada
# (§16.1) e no callback registrado (§16.2, "Comercial: Oportunidade + CALLBACK" com Prospect ainda
# Qualificado, §8.2) -- exigir a frente bloquearia o no-show dessa reunião e a propensão dessa
# oportunidade, que são justamente ações do Comercial (lacuna registrada na PR do CP-05).
#
# Máquina mínima (§8.4): Oportunidade → Em acompanhamento → Ganho / Perdido. Resultado terminal só
# a partir de Em acompanhamento.
module OperationalEngine
  module ComercialActionGuard
    class InvalidContextError < StandardError; end

    ETAPAS_ABERTAS = %w[oportunidade em_acompanhamento].freeze
    TRANSICOES = { 'oportunidade' => %w[em_acompanhamento], 'em_acompanhamento' => %w[ganho perdido] }.freeze

    def self.oportunidade_aberta?(lead)
      ETAPAS_ABERTAS.include?(lead.etapa_comercial) && lead.resultado_comercial_em_aberto?
    end

    def self.ensure_oportunidade_aberta!(lead, acao:)
      return if oportunidade_aberta?(lead)

      raise InvalidContextError, "#{acao} exige uma oportunidade Comercial aberta (etapa atual: #{lead.etapa_comercial || 'nenhuma'})"
    end

    def self.ensure_transicao!(lead, para:)
      ensure_oportunidade_aberta!(lead, acao: "mover para #{para}")
      return if TRANSICOES.fetch(lead.etapa_comercial, []).include?(para)

      raise InvalidContextError, "transição Comercial não permitida: #{lead.etapa_comercial} → #{para} (§8.4)"
    end
  end
end
