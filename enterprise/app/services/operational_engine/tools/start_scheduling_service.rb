# acao_sugerida = iniciar_agendamento (SSOT §12.4, S-4 parte 2). Só marca "começou a negociar
# horário" -- agendamento_status: em_andamento. NUNCA confirma sozinho: confirmado só nasce de um
# calendar_event_id real, via ScheduleMeetingService (S-5/Contrato B), que continua sendo o único
# caminho de conversão de verdade. Recusa (blocked) quando já existe um compromisso real em curso
# -- reabrir "vou agendar" por cima de um agendamento confirmado ou de um callback já combinado
# seria o Engine aceitando uma transição que o §16 não define.
#
# CP-01 (P1-018-05): todas as guardas dentro do with_lock -- um callback registrado ou uma reunião
# confirmada enquanto esta ação esperava não é sobrescrito para em_andamento. A restrição a
# Prospect Qualificado (P1-018-03) é do CP-04.
module OperationalEngine
  module Tools
    class StartSchedulingService
      ESTADOS_COM_COMPROMISSO_ATIVO = %w[confirmado callback_registrado callback_realizado].freeze

      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        result = lead.with_lock do
          reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead, nao_contatar: true)
          next { ok: false, reason: reason } if reason
          if ESTADOS_COM_COMPROMISSO_ATIVO.include?(lead.agendamento_status)
            next { ok: false, reason: 'já existe um compromisso ativo para este lead' }
          end
          next { ok: true } if lead.agendamento_status_em_andamento?

          lead.update!(agendamento_status: 'em_andamento')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'agendamento_iniciado', source: 'lavinia',
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
