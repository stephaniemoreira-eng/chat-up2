# acao_sugerida = ativar_nao_contatar (SSOT §12.4, S-4 parte 2). Sinal de opt-out -- ao contrário
# das outras ações, não tem guarda de estado nenhuma: um pedido de "não me contate mais" vale
# mesmo por cima de um agendamento confirmado, de atendimento humano ou qualquer outro estado. Não
# cancela sozinho um evento existente no Google Calendar -- o §19.2 não pede isso e seria decidir
# automaticamente por uma ação irreversível.
#
# CP-01 (P0-018-01, §19.2/§28.25): além da flag, cancela TODA automação futura do lead --
# recovery encerrada, próxima recovery nula, não aguarda mais resposta (sem timer que nasça disso)
# e as ativações outbound ainda pendentes do contato viram "cancelled". Mesmo que alguma automação
# já preparada escape disso (um nudge do up2-agents, por exemplo), o OutboundSendGate relê
# nao_contatar no post e bloqueia contato proativo. Inbound posterior do contato continua podendo
# ser respondido e NADA aqui ou no InboundProcessor limpa a flag (§28.26).
module OperationalEngine
  module Tools
    class ActivateDoNotContactService
      AUTOMACAO_ENCERRADA = { aguardando_resposta: false, recuperacao_status: 'inativa', proxima_recuperacao_em: nil }.freeze

      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        lead.with_lock do
          if lead.nao_contatar?
            # Replay/idempotência: sem evento novo, mas a automação continua garantidamente desligada.
            lead.update!(AUTOMACAO_ENCERRADA) if automacao_pendente?(lead)
            next
          end

          lead.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar', **AUTOMACAO_ENCERRADA)
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'nao_contatar_ativado', source: 'lavinia',
                                                metadata: { correlation_id: SecureRandom.uuid })
          OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'nao_contatar_ativado')
        end

        cancel_pending_activations(lead)
        OperationalEngine::ProjectionReconciler.flush(lead)
        { ok: true }
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end

      private

      def automacao_pendente?(lead)
        lead.aguardando_resposta? || lead.recuperacao_status_ativa? || lead.proxima_recuperacao_em.present?
      end

      # Fora do lock do lead (outro banco): se falhar no meio, o gate ainda barra pela flag.
      def cancel_pending_activations(lead)
        contact_id = OperationalEngine::Tools::ResolveLeadFromConversation
                     .conversation(account: @account, conversation_id: @conversation_id)&.contact_id
        return if contact_id.blank?

        # CP-13 (P1-VAL-12, §19.2/28.25): tentativa de recovery autorizada também é cancelada.
        [OperationalEngine::OriginationActivation, OperationalEngine::RecoveryActivation].each do |klass|
          klass.pending_for_contact(account_id: @account.id, contact_id: contact_id).each do |activation|
            activation.transition!('cancelled', motivo: 'nao_contatar') if activation.lead_id == lead.lead_id
          end
        end
      end
    end
  end
end
