# CP-02 (P0-019-01; SSOT §23.3): a rede de segurança da confirmação de envio real. Roda a cada tick
# do DispatcherJob, antes de originar: procura aberturas já gravadas (OriginationActivation
# consumida, com message_id) cujo provider já confirmou (source_id presente) mas cujo lead ainda não
# registrou o primeiro contato -- ou seja, a confirmação inline falhou E o retry do job também
# (ou nem chegou a ser enfileirado). Reaplica o ConfirmOutboundSendService, que é idempotente.
#
# Ancorado em estado durável (a conversa + a Message), não na transição efêmera do source_id. Janela
# limitada (LOOKBACK) e lote limitado (BATCH) pra não virar varredura cara; tudo que ele recupera é
# logado (observável).
module OperationalEngine
  class OutboundConfirmationReconciler
    LOOKBACK = 7.days
    BATCH = 50

    def self.call(account_id:)
      new(account_id).call
    end

    def initialize(account_id)
      @account_id = account_id
    end

    # Retorna quantas confirmações foram recuperadas.
    def call
      recovered = pending_messages.count do |message|
        next false unless unconfirmed_lead?(message)

        recover(message)
      end
      recovered + pending_recovery_messages.count { |message| recover(message) }
    end

    private

    def recover(message)
      Rails.logger.warn("[OperationalEngine::OutboundConfirmationReconciler] recuperando confirmação message_id=#{message.id}")
      OperationalEngine::ConfirmOutboundSendService.call(message: message)
      true
    end

    def pending_messages
      confirmed_messages(consumed_conversations(OperationalEngine::OriginationActivation::KEY).where(created_at: LOOKBACK.ago..),
                         OperationalEngine::OriginationActivation::KEY)
    end

    # CP-13 (P1-VAL-12): o mesmo para a tentativa de recovery WhatsApp -- post gravado (consumed) e já
    # confirmado pelo provedor, mas a tentativa ainda não registrada no Engine (sem `confirmed`).
    # O serviço é idempotente (a tentativa só incrementa uma vez).
    def pending_recovery_messages
      key = OperationalEngine::RecoveryActivation::KEY
      confirmed_messages(consumed_conversations(key).where(last_activity_at: LOOKBACK.ago..), key)
    end

    def consumed_conversations(key)
      ::Conversation.where(account_id: @account_id).where("additional_attributes -> '#{key}' ->> 'status' = ?", 'consumed')
    end

    def confirmed_messages(conversations, key)
      message_ids = conversations.limit(BATCH).filter_map { |conversation| conversation.additional_attributes.dig(key, 'message_id') }
      ::Message.where(id: message_ids).where.not(source_id: [nil, ''])
    end

    def unconfirmed_lead?(message)
      phone = message.conversation.contact&.phone_number
      return false if phone.blank?

      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: @account_id, telefone: phone)
      lead.present? && lead.primeiro_contato_em.nil?
    end
  end
end
