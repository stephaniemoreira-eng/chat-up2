# acao_sugerida = encerrar_nao_qualificado (SSOT §12.4, S-4 parte 2). Diferente de
# CloseAsNotInterestedService: aqui a qualificacao_status também vira nao_qualificado -- "não
# qualificado" É um julgamento de qualificação, ao contrário de "sem interesse". Mesma recusa por
# agendamento confirmado que o CloseAsNotInterestedService.
module OperationalEngine
  module Tools
    class CloseAsUnqualifiedService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        return { ok: false, reason: 'lead tem um agendamento confirmado' } if lead.agendamento_status_confirmado?

        lead.with_lock do
          next if lead.lead_status_encerrado? && lead.motivo_encerramento == 'nao_qualificado'

          lead.update!(lead_status: 'encerrado', motivo_encerramento: 'nao_qualificado', qualificacao_status: 'nao_qualificado')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'encerrado_nao_qualificado', source: 'lavinia',
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
