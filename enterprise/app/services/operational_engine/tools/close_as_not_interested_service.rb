# acao_sugerida = encerrar_sem_interesse (SSOT §12.4, S-4 parte 2). Encerra o lead como "sem
# interesse" -- não mexe em qualificacao_status: falta de interesse não é a mesma coisa que
# "não qualificado" (esse é decisao_qualificacao/qualificacao_status, um julgamento diferente).
# Recusa quando já existe um agendamento confirmado: o Engine revalida o estado antes de agir
# (§12.4) em vez de aceitar um encerramento que contradiz um compromisso real.
module OperationalEngine
  module Tools
    class CloseAsNotInterestedService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        return { ok: false, reason: 'lead tem um agendamento confirmado' } if lead.agendamento_status_confirmado?

        lead.with_lock do
          next if lead.lead_status_encerrado? && lead.motivo_encerramento == 'sem_interesse'

          lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'encerrado_sem_interesse', source: 'lavinia',
                                                metadata: { correlation_id: SecureRandom.uuid })
        end

        OperationalEngine::SalesProjectionSync.call(lead)
        OperationalEngine::ComercialProjectionSync.call(lead)
        { ok: true }
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end
    end
  end
end
