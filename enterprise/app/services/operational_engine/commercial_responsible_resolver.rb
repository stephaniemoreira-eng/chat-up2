# CP-05 (P1-018-01; SSOT §17.2 "responsavel_atual_id = Danilo/outro comercial"). Resolução ISOLADA
# do responsável Comercial do handoff real.
#
# LACUNA REGISTRADA (PR do CP-05, decisão pendente): o SSOT diz QUEM (Danilo/outro comercial), mas
# não diz COMO o Engine escolhe esse usuário quando o handoff é pedido pela Lavínia, sem nenhum
# humano no request. Não existe hoje configuração por conta que aponte o responsável Comercial
# (UpSales::AgentTenant, AgentSlot, Sales::Pipeline -- nenhum tem esse dado), nem regra de
# rodízio/equipe no SSOT. Então este resolver NÃO inventa uma regra:
#
# - se um humano já é o responsável atual (Danilo interveio durante a Prospecção, §18.4), ele
#   continua sendo o responsável -- nada é trocado nem apagado;
# - senão devolve nil: o handoff real completa todas as outras dimensões do §17.2 e o responsável
#   fica pendente, explícito no retorno da ação (`responsavel_pendente: true`) e no evento
#   `handoff_comercial`. Um humano da conta o assume pelo "Assumir" (TakeoverService), que grava
#   `responsavel_atual_id = usuário` (§18.2).
#
# Quando a regra for decidida (ex.: usuário Comercial configurado por conta), ela entra AQUI e
# em nenhum outro lugar. Atenção ao decidir: com responsável preenchido no próprio handoff, a
# resposta pública do turno que fez o handoff deixa de ser liberada pelo OutboundSendGate
# (#handoff_reply_allowed? exige responsável nulo -- decisão de 23/09/2026).
module OperationalEngine
  class CommercialResponsibleResolver
    def self.call(lead:)
      lead.responsavel_atual_id.presence
    end
  end
end
