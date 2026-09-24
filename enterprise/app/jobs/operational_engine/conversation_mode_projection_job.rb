# CP-16A (P2-VAL-16; decisão da Stéphanie em 24/09/2026: responsável Comercial do handoff = Danilo,
# configurado por conta). Reprojeta o modo de atendimento na conversa do canal DEPOIS que fecha a
# janela da resposta do turno do handoff -- a ConversationModeProjection não abre a conversa enquanto
# essa resposta ainda pode sair (ver o cabeçalho dela). Idempotente: recalcula da fotografia atual do
# lead; se o lead voltou para a Lavínia ou a conversa já foi aberta/resolvida, não faz nada novo. Uma
# falha aqui não perde nada: o próximo pedido de projeção do lead recalcula o mesmo estado.
module OperationalEngine
  class ConversationModeProjectionJob < ApplicationJob
    queue_as :default

    def perform(lead_id)
      lead = OperationalEngine::Lead.find_by(lead_id: lead_id)
      OperationalEngine::ConversationModeProjection.call(lead) if lead
    end
  end
end
