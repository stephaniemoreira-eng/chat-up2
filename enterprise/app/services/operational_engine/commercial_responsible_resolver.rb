# CP-05 (P1-018-01; SSOT §17.2 "responsavel_atual_id = Danilo/outro comercial"). Resolução ISOLADA
# do responsável Comercial do handoff real -- a regra mora AQUI e em nenhum outro lugar.
#
# O SSOT diz QUEM (Danilo/outro comercial), mas não dizia COMO o Engine escolhe esse usuário quando o
# handoff é pedido pela Lavínia, sem nenhum humano no request (lacuna registrada no PR do CP-05).
#
# CP-16A (P2-VAL-16; decisão da Stéphanie em 24/09/2026): o responsável Comercial do handoff pedido
# pela Lavínia é o Danilo -- resposta dela: "DANILO". Implementado como configuração POR CONTA
# (UpSales::AgentTenant#commercial_responsible_user_id, editável no Super Admin de configuração de
# agente), nunca como nome/ID fixo no código. Ordem:
#
# 1. um humano já é o responsável atual (Danilo interveio durante a Prospecção, §18.4) -> continua
#    sendo ele; nada é trocado nem apagado;
# 2. senão, o usuário Comercial configurado na conta (se ainda for usuário da conta);
# 3. senão nil: o handoff completa as outras dimensões do §17.2 e o responsável fica pendente,
#    explícito no retorno (`responsavel_pendente: true`) e no evento `handoff_comercial`; um humano o
#    assume pelo "Assumir" (TakeoverService, §18.2) -- comportamento do CP-05.
#
# Com o responsável preenchido PELO handoff, a resposta pública do próprio turno do handoff continua
# liberada (decisão de 23/09/2026, "Allow only that reply"): ver OutboundSendGate#handoff_reply_allowed?
# e ConversationModeProjection, que distinguem o responsável vindo do handoff de um humano que
# assumiu depois.
module OperationalEngine
  class CommercialResponsibleResolver
    def self.call(lead:)
      lead.responsavel_atual_id.presence || configured_for(lead.conta_id)
    end

    def self.configured_for(conta_id)
      UpSales::AgentTenant.find_by(account_id: conta_id)&.commercial_responsible_user_id_for_handoff
    end
  end
end
