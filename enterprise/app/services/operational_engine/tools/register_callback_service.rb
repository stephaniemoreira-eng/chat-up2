# S-5 / Contrato B / SSOT §16: registra que um callback foi COMBINADO -- não que foi realizado
# (isso é ação humana separada, fora do escopo do S-5, ver §21.2). Explícito no SSOT: "Callback
# registrado não é conversão" -- por isso este serviço nunca toca conversao_em/tipo_conversao.
module OperationalEngine
  module Tools
    class RegisterCallbackService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        lead.with_lock do
          lead.update!(
            agendamento_status: 'callback_registrado',
            # "cria/mantém oportunidade Comercial": só define se ainda não havia nenhuma -- não
            # rebaixa um lead que já esteja em_acompanhamento/ganho/perdido.
            **(lead.etapa_comercial.nil? ? { etapa_comercial: 'oportunidade' } : {})
          )
          OperationalEngine::LeadEvent.create!(
            lead: lead,
            event_type: 'callback_registrado',
            source: 'lavinia',
            metadata: { correlation_id: SecureRandom.uuid }
          )
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
