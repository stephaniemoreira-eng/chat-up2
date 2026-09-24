# CP-01 (P1-018-05, SSOT §12.4 "modo_atendimento=humano implica resposta pública vazia/nenhuma
# ação da Lavínia", §23.2). Guarda comum das ações que a Lavínia pede ao Engine. Tem que ser
# chamada DENTRO do `lead.with_lock` da mutação -- `with_lock` relê a linha, então o que se avalia
# aqui é o estado atual, não a fotografia de quando a ação foi preparada. Um humano que assumiu
# enquanto a ação esperava o lock vence.
#
# ativar_nao_contatar NÃO usa esta guarda: opt-out prevalece sobre qualquer estado.
module OperationalEngine
  module Tools
    module LaviniaActionGuard
      HUMANO = 'lead em atendimento humano'.freeze
      NAO_CONTATAR = 'lead está em não-contatar'.freeze
      ENCERRADO = 'lead encerrado'.freeze

      def self.blocked_reason(lead, nao_contatar: false)
        return HUMANO if lead.modo_atendimento_humano?
        return NAO_CONTATAR if nao_contatar && lead.nao_contatar?

        nil
      end
    end
  end
end
