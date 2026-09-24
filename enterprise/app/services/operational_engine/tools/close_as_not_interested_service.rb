# acao_sugerida = encerrar_sem_interesse (SSOT §12.4, S-4 parte 2). Encerra o lead como "sem
# interesse" -- não mexe em qualificacao_status: falta de interesse não é a mesma coisa que
# "não qualificado" (esse é decisao_qualificacao/qualificacao_status, um julgamento diferente).
# Recusa quando já existe um agendamento confirmado: o Engine revalida o estado antes de agir
# (§12.4) em vez de aceitar um encerramento que contradiz um compromisso real.
#
# CP-01 (P1-018-05): toda guarda é avaliada dentro do with_lock (estado relido) -- uma reunião
# confirmada ou um humano que assumiu enquanto esta ação esperava vence a ação antiga.
module OperationalEngine
  module Tools
    class CloseAsNotInterestedService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        result = lead.with_lock do
          reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead)
          next { ok: false, reason: reason } if reason
          next { ok: false, reason: 'lead tem um agendamento confirmado' } if lead.agendamento_status_confirmado?
          next { ok: true } if lead.lead_status_encerrado? && lead.motivo_encerramento == 'sem_interesse'

          lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'encerrado_sem_interesse', source: 'lavinia',
                                                metadata: { correlation_id: SecureRandom.uuid })
          OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'encerrado_sem_interesse')
          { ok: true }
        end
        return result unless result[:ok]

        OperationalEngine::ProjectionReconciler.flush(lead)
        result
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end
    end
  end
end
