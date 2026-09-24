# CP-03 (P1-017-01, P1-021-03; SSOT §12.3): a parte "mensagens" do Snapshot, montada pelo Engine em
# torno do DISPARADOR do turno -- não "a última mensagem agora". Com duas mensagens próximas, cada
# turno recebe exatamente a sua como mensagem_atual, e o histórico recente termina nela (nada do que
# chegou depois vaza para um turno anterior).
#
# "Não despejar todo o histórico" (§12.3): só as RECENT_LIMIT mensagens públicas mais recentes até o
# disparador, inclusive. Notas privadas e mensagens de atividade ficam de fora (não são conversa).
module OperationalEngine
  class TurnMessages
    class InvalidTrigger < StandardError; end

    RECENT_LIMIT = 10

    def self.call(conversation:, message_id:)
      new(conversation, message_id).call
    end

    def initialize(conversation, message_id)
      @conversation = conversation
      @message_id = message_id
    end

    # Sem message_id (primeiro contato: ninguém falou ainda) -> sem mensagem atual, histórico vazio.
    def call
      return { mensagem_atual: nil, mensagens_recentes_relevantes: [] } if @message_id.blank?

      trigger = @conversation.messages.find_by(id: @message_id)
      raise InvalidTrigger, 'mensagem não pertence à conversa' if trigger.nil?

      {
        mensagem_atual: { message_id: trigger.id.to_s, texto: trigger.content, timestamp: trigger.created_at.iso8601 },
        mensagens_recentes_relevantes: recent_until(trigger).map { |message| serialize(message) }
      }
    end

    private

    def recent_until(trigger)
      @conversation.messages
                   .where(private: false, message_type: %i[incoming outgoing template])
                   .where('messages.id <= ?', trigger.id)
                   .reorder(id: :desc)
                   .limit(RECENT_LIMIT)
                   .to_a
                   .reverse
    end

    def serialize(message)
      { message_id: message.id.to_s, autor: autor(message), texto: message.content, timestamp: message.created_at.iso8601 }
    end

    def autor(message)
      return 'lead' if message.incoming?
      return 'humano' if message.sender_type == 'User'

      'lavinia'
    end
  end
end
