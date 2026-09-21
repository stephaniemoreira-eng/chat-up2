# Elegibilidade (§10.2) + FIFO (§10.3) + capacidade (§10.4): "me dê os próximos leads que posso
# abordar agora". É a peça que o dispatcher da Fase 6 (ainda não escrito -- falta Lavínia gerar a
# mensagem, Fase 4) vai chamar em loop; até lá, este serviço já é útil sozinho pra inspecionar o
# estado real do Backlog.
#
# "Não sendo trabalhado de forma incompatível" e "modo operacional compatível" (§10.2) são
# interpretados aqui, de forma estreita, como modo_atendimento=lavinia: hoje nenhum lead em
# Backlog tem como estar em modo_atendimento=humano (TakeoverService só age sobre uma conversa
# que já existe, e Backlog é justamente quem ainda não tem conversa) -- é defesa antecipada, não
# um caso real ainda observável.
module OperationalEngine
  class BacklogSelector
    def self.proximos(conta_id:, agora: Time.current)
      new(conta_id: conta_id, agora: agora).proximos
    end

    def initialize(conta_id:, agora: Time.current)
      @conta_id = conta_id
      @agora = agora
    end

    def proximos
      capacidade = OperationalEngine::BacklogCapacity.disponivel(conta_id: @conta_id, agora: @agora)
      return OperationalEngine::Lead.none if capacidade.zero?

      elegiveis.order(etapa_entrou_em: :asc).limit(capacidade)
    end

    private

    def elegiveis
      OperationalEngine::Lead
        .where(conta_id: @conta_id, etapa_prospect: 'backlog', lead_status: 'ativo',
               nao_contatar: false, modo_atendimento: 'lavinia')
        # .where.not(relacao_atual: 'cliente_atual') excluiria silenciosamente as linhas com
        # relacao_atual NULL (NOT (NULL = x) é NULL em SQL, não TRUE) -- a maioria dos leads de
        # Backlog hoje, já que a coluna não tem default. Forma explícita, sem essa armadilha.
        .where("relacao_atual IS NULL OR relacao_atual != ?", 'cliente_atual')
    end
  end
end
