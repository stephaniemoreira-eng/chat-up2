# SSOT §5.4/§10.6, Risco §14.1 do plano do Marco 1 -- a pendência que o próprio
# OperationalEngineListener deixou marcada desde a Fase 3 ("confirmação de envio real (source_id)
# é Fase 6"). Chamado só quando `source_id` acabou de sair de branco pra presente numa mensagem
# nossa -- não em MESSAGE_CREATED, que é o gatilho errado (§10.6, §23.3): a `Message` nasce com
# `status: 'sent'` por default mesmo quando o Baileys está fora do ar, e `source_id` continua nil
# até a confirmação real chegar. Gravar `primeiro_contato_em` reagindo à criação, não à
# confirmação, registraria um envio que nunca aconteceu.
#
# `Message#update!` (não `update_columns`) é quem grava o `source_id` real
# (Whatsapp::Session::Outbound::SourceIdReservation#write), então `after_update_commit` do
# Message já dispara MESSAGE_UPDATED de forma confiável nesse momento -- o fallback do plano
# (`after_update_commit` num overlay) não é necessário, o Chatwoot nativo já faz isso.
module OperationalEngine
  class ConfirmOutboundSendService
    def self.call(message:)
      new(message).call
    end

    def initialize(message)
      @message = message
    end

    def call
      telefone = @message.conversation.contact&.phone_number
      return if telefone.blank?

      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: @message.account_id, telefone: telefone)
      return if lead.nil?

      changed = false

      lead.with_lock do
        next unless lead.primeiro_contato_em.nil?

        lead.update!(
          primeiro_contato_em: Time.current,
          # Só o caminho outbound/Backlog nasce em backlog (§10.5/§10.6) -- um lead inbound já
          # nasce em em_conversa (InboundProcessor), então esta transição nunca dispara indevida
          # pra ele.
          **(lead.etapa_prospect_backlog? ? { etapa_prospect: 'contatado', etapa_entrou_em: Time.current } : {})
        )
        OperationalEngine::LeadEvent.create!(
          lead: lead, event_type: 'primeiro_contato_enviado', source: 'system',
          metadata: { message_id: @message.id, source_id: @message.source_id, correlation_id: SecureRandom.uuid }
        )
        changed = true
      end

      return unless changed

      OperationalEngine::SalesProjectionSync.call(lead)
      OperationalEngine::ComercialProjectionSync.call(lead)
    end
  end
end
