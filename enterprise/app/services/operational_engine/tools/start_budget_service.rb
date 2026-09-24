# acao_sugerida = iniciar_orcamento (SSOT §12.4, S-4 parte 2). O agente sinaliza que a conversa
# entrou em dimensionamento de orçamento -- não carrega valor nenhum ainda, só o início da
# etapa. Idempotente: continuar sinalizando depois que já saiu de nao_solicitado não é erro.
#
# CP-01 (P1-018-05): nao_contatar/humano checados dentro do with_lock -- um opt-out que entrou
# enquanto esta ação esperava vence.
module OperationalEngine
  module Tools
    class StartBudgetService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        result = lead.with_lock do
          reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead, nao_contatar: true)
          next { ok: false, reason: reason } if reason
          next { ok: true } unless lead.orcamento_status_nao_solicitado?

          lead.update!(orcamento_status: 'em_dimensionamento')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'orcamento_iniciado', source: 'lavinia',
                                                metadata: { correlation_id: SecureRandom.uuid })
          { ok: true }
        end
        return result unless result[:ok]

        OperationalEngine::SalesProjectionSync.call(lead)
        OperationalEngine::ComercialProjectionSync.call(lead)
        result
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end
    end
  end
end
