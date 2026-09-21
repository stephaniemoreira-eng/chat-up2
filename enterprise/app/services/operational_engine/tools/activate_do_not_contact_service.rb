# acao_sugerida = ativar_nao_contatar (SSOT §12.4, S-4 parte 2). Sinal de opt-out -- ao contrário
# das outras ações, não tem guarda de estado nenhuma: um pedido de "não me contate mais" vale
# mesmo por cima de um agendamento confirmado ou qualquer outro estado. Não cancela sozinho um
# evento existente no Google Calendar -- isso exigiria decidir automaticamente por uma ação
# irreversível (cancelar reunião) que o §12.4 não pede aqui; fica registrado como pendência.
module OperationalEngine
  module Tools
    class ActivateDoNotContactService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        lead.with_lock do
          next if lead.nao_contatar?

          lead.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'nao_contatar_ativado', source: 'lavinia',
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
