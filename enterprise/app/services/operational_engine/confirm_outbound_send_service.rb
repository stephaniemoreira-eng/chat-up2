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
#
# CP-02:
# - P0-019-01: a confirmação é recuperável -- este serviço é idempotente por construção (o fato
#   só é gravado enquanto primeiro_contato_em é nulo, sob lock) e pode ser reexecutado pela mesma
#   mensagem quantas vezes for preciso: pelo ConfirmOutboundSendJob (retry com backoff quando a
#   chamada inline falha) e pelo OutboundConfirmationReconciler (varredura no tick do dispatcher).
#   A projeção roda SEMPRE no fim, mesmo sem mudança -- um retry depois de falha só na projeção
#   repara o CRM sem recriar o evento de negócio.
# - P1-019-01 (§9/§10.6): no primeiro envio real, entrada_operacao_em = agora (write-once -- um
#   lead inbound já tem a sua e nunca é sobrescrito).
# - P1-019-02 (§7.3/§7.4/§10.6): Backlog → Contatado grava também etapa_alterada
#   {de, para, motivo: primeiro_contato_enviado}; sem mudança real de etapa, nenhum evento falso.
#
# CP-13 (P1-VAL-12): idempotente também para o Recovery -- armar só acontece com o ciclo inativo e
# sem timer, e a tentativa só incrementa se o lead ainda está exatamente uma tentativa antes dela.
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

      lead.with_lock do
        if lead.primeiro_contato_em.nil?
          record_first_contact(lead)
          OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'primeiro_contato')
        end
        # CP-13 (P1-VAL-12; SSOT §15.2, §15.8, §23.3): a mesma confirmação real do provedor é o que
        # conta uma tentativa de recovery como enviada, ou arma o ciclo depois de uma mensagem da
        # Lavínia que ficou aguardando resposta. Depois do primeiro contato (mesmo lock), para que a
        # abertura já tenha levado o lead a Contatado -- e a cadência seja a de "nunca respondeu".
        OperationalEngine::RecoveryCycle.on_send_confirmed(lead, @message)
      end

      # CP-08 (resíduo do CP-05, P1-025-04): projeção pelo mecanismo durável. Também no no-op
      # (confirmação repetida): se uma projeção anterior ficou pendente, ela é reparada aqui.
      OperationalEngine::ProjectionReconciler.flush(lead)
    end

    private

    def record_first_contact(lead)
      now = Time.current
      from_backlog = lead.etapa_prospect_backlog?
      lead.update!(
        primeiro_contato_em: now,
        **(lead.entrada_operacao_em.nil? ? { entrada_operacao_em: now } : {}),
        # Só o caminho outbound/Backlog nasce em backlog (§10.5/§10.6) -- um lead inbound já nasce
        # em em_conversa (InboundProcessor), então esta transição nunca dispara indevida pra ele.
        **(from_backlog ? { etapa_prospect: 'contatado', etapa_entrou_em: now } : {})
      )
      write_event(lead, 'primeiro_contato_enviado', message_id: @message.id, source_id: @message.source_id)
      write_event(lead, 'etapa_alterada', de: 'backlog', para: 'contatado', motivo: 'primeiro_contato_enviado') if from_backlog
    end

    def write_event(lead, event_type, **metadata)
      OperationalEngine::LeadEvent.create!(
        lead: lead, event_type: event_type, source: 'system',
        metadata: metadata.merge(correlation_id: SecureRandom.uuid)
      )
    end
  end
end
