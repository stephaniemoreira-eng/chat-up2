# CP-06 (P1-026-01, RISK-026-01; SSOT §4 "CRM é projeção", §18.2 "Lavínia para", §18.3 "depois:
# modo_atendimento = lavinia"). Projeta `modo_atendimento` na conversa do canal (Chatwoot).
#
# O up2-agents decide se a Lavínia atende uma conversa pelo espelho da conversa (status + tipo do
# responsável -- `shouldBotHandle`): só `pending` e sem usuário humano atribuído. Sem esta projeção:
# - Assumir pelo card deixava a conversa `pending`: a Lavínia continuava rodando turnos (recusados
#   no post pelo OutboundSendGate, mas gastando LLM e gerando retry);
# - Devolver depois de um humano responder deixava a conversa `open`/atribuída: a Lavínia nunca
#   voltava, apesar do Engine dizer `lavinia`.
#
# Derivada só da fotografia do lead (idempotente, roda dentro do ProjectionReconciler -- falha é
# reconciliada como qualquer outra projeção):
# - humano COM responsável -> `pending` vira `open` (a Lavínia deixa de atender a conversa);
# - humano SEM responsável (handoff com responsável Comercial pendente, lacuna do CP-05) -> não
#   toca: a resposta do próprio turno do handoff continua liberada (decisão de 23/09/2026) e o
#   OutboundSendGate barra o resto;
# - lavinia -> `open` vira `pending` e um usuário humano atribuído é removido.
# Conversa resolvida/adiada e inbox sem bot ativo nunca são tocadas.
#
# CP-16A (P2-VAL-16; decisão da Stéphanie em 24/09/2026: responsável Comercial do handoff pedido pela
# Lavínia = "DANILO", configurado por conta): o handoff agora pode deixar o lead humano COM
# responsável. Abrir a conversa na hora faria o up2-agents parar ANTES de postar a resposta do próprio
# turno do handoff (que o OutboundSendGate libera -- decisão de 23/09/2026). Solução: enquanto a
# janela dessa resposta estiver aberta (OperationalEngine::HandoffReplyWindow -- responsável gravado
# pelo próprio handoff, dentro da janela técnica, nenhuma mensagem/fato humano depois) a conversa NÃO
# é aberta; um OperationalEngine::ConversationModeProjectionJob reprojeta logo depois que a janela
# fecha, e aí ela vira `open`. Se um humano escrever ou assumir antes disso, a janela fecha e a
# próxima projeção (inclusive a do job) abre na hora.
module OperationalEngine
  class ConversationModeProjection
    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    def call
      conversation = target_conversation
      return if conversation.nil?

      changes = desired_changes(conversation)
      conversation.update!(changes) if changes.present?
    end

    private

    attr_reader :lead

    def target_conversation
      return if lead.upsales_conversation_atual_id.blank?

      conversation = ::Conversation.find_by(id: lead.upsales_conversation_atual_id, account_id: lead.conta_id)
      conversation if conversation && %w[open pending].include?(conversation.status) && conversation.inbox.active_bot?
    end

    def desired_changes(conversation)
      if lead.modo_atendimento_lavinia?
        lavinia_changes(conversation)
      elsif lead.responsavel_atual_id.present? && conversation.pending?
        handoff_reply_pending?(conversation) ? {} : { status: :open }
      else
        {}
      end
    end

    # CP-16A: adia o `open` até a resposta do turno do handoff (ver cabeçalho) e agenda a reprojeção.
    def handoff_reply_pending?(conversation)
      window = OperationalEngine::HandoffReplyWindow.new(lead, conversation)
      return false unless window.open_with_handoff_responsible?

      OperationalEngine::ConversationModeProjectionJob.set(wait_until: window.closes_at + 1.second).perform_later(lead.lead_id)
      true
    end

    def lavinia_changes(conversation)
      {}.tap do |changes|
        changes[:status] = :pending if conversation.open?
        changes[:assignee_id] = nil if conversation.assignee_id.present?
      end
    end
  end
end
