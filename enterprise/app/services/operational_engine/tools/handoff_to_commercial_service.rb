# acao_sugerida = handoff_comercial (SSOT §12.4/§17.1, S-4 parte 2). Diferente de
# TakeoverService (S-3/§18.2): aquele é um humano especifico clicando "Assumir" (precisa de
# user_id). Aqui é a própria Lavínia sinalizando "isto precisa de humano" sem que ninguém tenha
# reivindicado ainda -- então modo_atendimento vira humano com responsavel_atual_id continuando
# nulo ("precisa de humano", não "already claimed"). Um humano real assume depois pelo fluxo
# normal (TakeoverService), que já sabe lidar com um lead que chega em modo_atendimento=humano
# sem responsável.
#
# Mesmo motivo do §18.2 aplicado aqui: para de esperar resposta e desliga recovery -- a partir
# deste ponto a Lavínia não fala mais nesta conversa (§12.4: "modo_atendimento=humano implica
# resposta pública vazia").
module OperationalEngine
  module Tools
    class HandoffToCommercialService
      def initialize(account:, conversation_id:, motivo_handoff:)
        @account = account
        @conversation_id = conversation_id
        @motivo_handoff = motivo_handoff
      end

      def call
        return { ok: false, reason: 'motivo_handoff inválido' } unless OperationalEngine::Lead.motivo_handoffs.key?(@motivo_handoff)

        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        return { ok: false, reason: 'lead está em não-contatar' } if lead.nao_contatar?

        lead.with_lock do
          next if lead.modo_atendimento_humano?

          lead.update!(
            modo_atendimento: 'humano',
            modo_atendimento_entrou_em: Time.current,
            motivo_handoff: @motivo_handoff,
            aguardando_resposta: false,
            recuperacao_status: 'inativa',
            proxima_recuperacao_em: nil,
            # mesma regra do RegisterCallbackService: cria a oportunidade Comercial se ainda não
            # havia nenhuma, nunca rebaixa uma que já avançou.
            **(lead.etapa_comercial.nil? ? { etapa_comercial: 'oportunidade' } : {})
          )
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'handoff_comercial', source: 'lavinia',
                                                metadata: { motivo_handoff: @motivo_handoff, correlation_id: SecureRandom.uuid })
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
