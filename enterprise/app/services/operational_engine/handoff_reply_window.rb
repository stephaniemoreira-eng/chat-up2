# A janela da resposta do turno que fez handoff_comercial (decisão da Stéphanie em 23/09/2026, lacuna
# do SSOT registrada no PR do CP-05/CP-06: "Allow only that reply"). Extraída do OutboundSendGate no
# CP-16A para que o gate e a ConversationModeProjection usem EXATAMENTE a mesma regra.
#
# A janela está aberta quando:
# - o lead está em modo humano por um handoff (motivo_handoff presente);
# - o último evento de modo é o handoff_comercial da própria Lavínia, dentro da janela técnica
#   (ENV UP_SALES_HANDOFF_REPLY_WINDOW_SECONDS, padrão 120s) -- uma intervenção humana registrada
#   depois o substitui;
# - nenhuma mensagem pública humana na conversa depois do handoff;
# - responsável: nulo (responsável Comercial pendente, CP-05) OU -- CP-16A (P2-VAL-16; decisão da
#   Stéphanie em 24/09/2026, responsável Comercial do handoff = "DANILO", configurado por conta) --
#   exatamente o responsável que o próprio evento handoff_comercial gravou
#   (transicoes.responsavel_atual_id.para), sem nenhum fato humano de responsável/intervenção depois.
#   Responsável que já existia antes do handoff (humano interveio na Prospecção, §18.4) ou que foi
#   trocado depois fecha a janela.
module OperationalEngine
  class HandoffReplyWindow
    # Fatos humanos que invalidam a janela com responsável preenchido pelo handoff.
    HUMAN_CLAIM_EVENTS = %w[responsavel_alterado intervencao_humana_iniciada intervencao_humana_encerrada].freeze
    MODE_EVENTS = %w[handoff_comercial intervencao_humana_iniciada intervencao_humana_encerrada].freeze

    def self.duration
      ENV.fetch('UP_SALES_HANDOFF_REPLY_WINDOW_SECONDS', '120').to_i.seconds
    end

    def initialize(lead, conversation)
      @lead = lead
      @conversation = conversation
    end

    def open?
      return false unless @lead.modo_atendimento_humano? && @lead.motivo_handoff.present?
      return false if handoff.nil? || human_message_since_handoff?

      @lead.responsavel_atual_id.blank? || responsible_set_by_handoff?
    end

    # CP-16A: a janela está aberta E o responsável foi gravado pelo próprio handoff -- o caso em que a
    # ConversationModeProjection adia o `open` da conversa até a janela fechar.
    def open_with_handoff_responsible?
      @lead.responsavel_atual_id.present? && open?
    end

    def closes_at
      handoff && (handoff.event_at + self.class.duration)
    end

    private

    def handoff
      return @handoff if defined?(@handoff)

      event = @lead.events.where(event_type: MODE_EVENTS).order(event_at: :desc).first
      @handoff = (event if event&.event_type == 'handoff_comercial' && event.source_lavinia? && event.event_at >= self.class.duration.ago)
    end

    def human_message_since_handoff?
      return false if @conversation.nil?

      @conversation.messages.outgoing.where(sender_type: 'User', private: false).exists?(['created_at >= ?', handoff.event_at])
    end

    def responsible_set_by_handoff?
      para = handoff.metadata.to_h.dig('transicoes', 'responsavel_atual_id', 'para')
      return false unless para.present? && para.to_s == @lead.responsavel_atual_id.to_s

      # >= de propósito: empate de timestamp conta como "depois" (falha fechado).
      @lead.events.where(source: 'human', event_type: HUMAN_CLAIM_EVENTS).where('event_at >= ?', handoff.event_at).none?
    end
  end
end
