# acao_sugerida = iniciar_orcamento (SSOT §12.4, S-4 parte 2). O agente sinaliza que a conversa
# entrou em dimensionamento de orçamento -- não carrega valor nenhum ainda, só o início da
# etapa. Idempotente: continuar sinalizando depois que já saiu de nao_solicitado não é erro.
module OperationalEngine
  module Tools
    class StartBudgetService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        return { ok: false, reason: 'lead está em não-contatar' } if lead.nao_contatar?

        lead.with_lock do
          next unless lead.orcamento_status_nao_solicitado?

          lead.update!(orcamento_status: 'em_dimensionamento')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'orcamento_iniciado', source: 'lavinia',
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
