# CP-13 (P1-VAL-12; SSOT §15.1-§15.4, §15.9, §7.3, §7.4, §19, §23.3): as transições de estado do
# Recovery no lead. Toda chamada roda DENTRO do `lead.with_lock` de quem chama (mesmo lock do
# OutboundSendGate/TakeoverService/InboundProcessor) e pede a projeção durável na mesma transação.
#
# Ciclo (recovery é estado transversal, não coluna do Kanban -- §15.1):
#
#   armado      -> recuperacao_status=inativa, tentativa=0, proxima_recuperacao_em=t1 (só o timer)
#   iniciado    -> recuperacao_status=ativa (a t1 venceu sem resposta; evento recuperacao_iniciada)
#   tentativa N -> tentativa_recuperacao=N depois do envio CONFIRMADO; proxima = próxima tentativa
#   esgotado    -> inativa, lead encerrado, motivo sem_resposta (recuperacao_esgotada + lead_encerrado)
#   respondido  -> qualquer resposta real: inativa, tentativa 0, proxima null (recuperacao_respondida
#                  quando o ciclo já estava ativo)
#
# Nascimento (§15.2 "Engine cria o ciclo/timer correspondente"): a saída estruturada da Lavínia é
# commitada ANTES do post (ApplyStructuredOutputService grava aguardando_resposta/ultimo_ponto), mas
# o timer só nasce quando o provedor confirma o envio real daquela mensagem (source_id -- §23.3
# "mudança de negócio só depois da confirmação da ação técnica"). Armar o timer não é "precisar de
# recovery": o ciclo só vira `ativa` (e só então entra no Dashboard §22.7) quando a primeira
# tentativa vence sem resposta.
module OperationalEngine
  class RecoveryCycle
    AUTOMATION_KIND = 'RECUPERACAO'.freeze

    class << self
      # Confirmação real (source_id) de uma mensagem pública nossa: ou é a tentativa de recovery em
      # andamento (incrementa), ou pode armar um ciclo novo.
      def on_send_confirmed(lead, message)
        # Conversa relida: a ativação pode ter sido consumida pelo gate depois de a mensagem carregar a sua.
        conversation = ::Conversation.find_by(id: message.conversation_id)
        activation = conversation && OperationalEngine::RecoveryActivation.for(conversation)
        if activation&.canal == 'whatsapp' && activation.message_id.to_s == message.id.to_s
          confirm_whatsapp!(lead, activation, message)
        else
          arm!(lead, message)
        end
      end

      def arm!(lead, message)
        return unless armable?(lead, message)

        proxima = OperationalEngine::RecoveryCadence.eligible_at(lead, tentativa: 1, baseline: Time.current)
        lead.update!(tentativa_recuperacao: 0, proxima_recuperacao_em: proxima, upsales_conversation_atual_id: message.conversation_id,
                     **(lead.upsales_contact_id.blank? ? { upsales_contact_id: message.conversation.contact_id } : {}))
        log(lead, "ciclo armado (#{OperationalEngine::RecoveryCadence.tipo(lead)}) proxima=#{proxima.iso8601}")
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'recuperacao_armada')
      end

      def start!(lead, conversation)
        lead.update!(recuperacao_status: 'ativa')
        write_event(lead, 'recuperacao_iniciada', **cycle_metadata(lead, conversation), elegivel_em: lead.proxima_recuperacao_em&.iso8601)
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'recuperacao_iniciada')
      end

      # §15.8 "tentativa só incrementa após envio bem-sucedido". Idempotente pelo próprio estado: só
      # incrementa se o lead ainda está exatamente uma tentativa antes desta.
      def confirm_whatsapp!(lead, activation, message)
        return if activation.status == 'confirmed'

        register_attempt!(lead, activation, 'recuperacao_mensagem_enviada', message_id: message.id, source_id: message.source_id,
                                                                            inbox_id: message.inbox_id, conversation_id: message.conversation_id)
        activation.transition!('confirmed', confirmed_message_id: message.id)
      end

      # Idempotente: reexecutar depois de um commit já feito não duplica nada.
      def confirm_email!(lead, activation)
        register_attempt!(lead, activation, 'recuperacao_email_enviado', email_message_id: activation.email_message_id)
      end

      # §15.9. Devolve o que havia antes (quem chama registra recuperacao_respondida com a
      # idempotência do próprio webhook) -- nil quando não havia nada pendente.
      def reset_on_reply!(lead)
        pending = lead.recuperacao_status_ativa? || lead.tentativa_recuperacao.positive? || lead.proxima_recuperacao_em.present?
        return nil unless pending

        before = { ativa: lead.recuperacao_status_ativa?, tentativa: lead.tentativa_recuperacao, ultimo_ponto: lead.ultimo_ponto }
        lead.update!(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: nil)
        before
      end

      # Revalidação do §15.8 falhou: o timer não faz mais sentido e não fica pendurado. Timers
      # antigos não ressuscitam (§18.3): um ciclo novo só nasce de um novo envio confirmado.
      def interrupt!(lead, motivos)
        before = { tentativa: lead.tentativa_recuperacao, estava_ativa: lead.recuperacao_status_ativa? }
        lead.update!(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: nil)
        write_event(lead, 'recuperacao_interrompida', motivos: Array(motivos), **before)
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'recuperacao_interrompida')
      end

      # §15.3/§15.4 "após esgotar: recovery inativa, lead encerrado, sem_resposta".
      def exhaust!(lead, **extra)
        correlation_id = SecureRandom.uuid
        metadata = { tentativas: lead.tentativa_recuperacao, cadencia: OperationalEngine::RecoveryCadence.tipo(lead),
                     ultimo_ponto: lead.ultimo_ponto }
        de = lead.lead_status
        lead.update!(recuperacao_status: 'inativa', proxima_recuperacao_em: nil, aguardando_resposta: false,
                     lead_status: 'encerrado', motivo_encerramento: 'sem_resposta')
        write_event(lead, 'recuperacao_esgotada', correlation_id: correlation_id, **metadata, **extra)
        write_event(lead, 'lead_encerrado', correlation_id: correlation_id, de: de, para: 'encerrado', motivo: 'sem_resposta')
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'recuperacao_esgotada')
      end

      def recovery_message?(message)
        attributes = message.content_attributes.is_a?(Hash) ? message.content_attributes.with_indifferent_access : {}
        attributes.dig(:up2_automation, :kind) == AUTOMATION_KIND
      end

      private

      def armable?(lead, message)
        return false unless message.sender_type == 'AgentBot' && !message.private?
        return false unless lead.aguardando_resposta? && lead.modo_atendimento_lavinia? && lead.lead_status_ativo? && !lead.nao_contatar?
        return false if lead.recuperacao_status_ativa? || lead.proxima_recuperacao_em.present? || recovery_message?(message)

        # Confirmação atrasada de uma mensagem mais antiga que a última fala do contato não arma nada.
        message.conversation.messages.incoming.where('created_at > ?', message.created_at).none?
      end

      def expecting?(lead, activation)
        lead.recuperacao_status_ativa? && lead.tentativa_recuperacao == activation.tentativa - 1
      end

      def already_applied?(lead, activation)
        lead.recuperacao_status_ativa? && lead.tentativa_recuperacao >= activation.tentativa
      end

      # O envio aconteceu de fato. Ciclo ainda esperando esta tentativa: incrementa e agenda a próxima.
      # Ciclo mudou no meio (o lead respondeu, humano assumiu): o fato fica registrado, o estado não.
      def register_attempt!(lead, activation, event_type, **extra)
        return advance!(lead, activation, event_type, **extra) if expecting?(lead, activation)
        return if already_applied?(lead, activation)

        write_event(lead, event_type, **attempt_metadata(lead, activation), **extra, ciclo_ativo: false)
      end

      def advance!(lead, activation, event_type, **extra)
        now = Time.current
        proxima = OperationalEngine::RecoveryCadence.eligible_at(lead, tentativa: activation.tentativa + 1, baseline: now)
        lead.update!(tentativa_recuperacao: activation.tentativa, proxima_recuperacao_em: proxima)
        write_event(lead, event_type, **attempt_metadata(lead, activation), **extra, proxima_recuperacao_em: proxima.iso8601)
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: event_type)
      end

      def attempt_metadata(lead, activation)
        { tentativa: activation.tentativa, canal: activation.canal, activation_id: activation.activation_id,
          cadencia: OperationalEngine::RecoveryCadence.tipo(lead), ultimo_ponto: lead.ultimo_ponto }
      end

      def cycle_metadata(lead, conversation)
        { cadencia: OperationalEngine::RecoveryCadence.tipo(lead), ultimo_ponto: lead.ultimo_ponto,
          inbox_id: conversation&.inbox_id, conversation_id: conversation&.id }
      end

      def write_event(lead, event_type, correlation_id: SecureRandom.uuid, **metadata)
        OperationalEngine::LeadEvent.create!(lead: lead, event_type: event_type, source: 'system', event_at: Time.current,
                                              metadata: metadata.merge(correlation_id: correlation_id))
      end

      def log(lead, text)
        Rails.logger.info("[OperationalEngine::RecoveryCycle] lead=#{lead.lead_id} #{text}")
      end
    end
  end
end
