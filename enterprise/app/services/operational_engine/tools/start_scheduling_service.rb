# acao_sugerida = iniciar_agendamento (SSOT §12.4, S-4 parte 2). Só marca "começou a negociar
# horário" -- agendamento_status: em_andamento. NUNCA confirma sozinho: confirmado só nasce de um
# calendar_event_id real, via ScheduleMeetingService (S-5/Contrato B), que continua sendo o único
# caminho de conversão de verdade. Recusa (blocked) quando já existe um compromisso real em curso
# -- reabrir "vou agendar" por cima de um agendamento confirmado ou de um callback já combinado
# seria o Engine aceitando uma transição que o §16 não define.
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
        return { ok: false, reason: 'lead está em não-contatar' } if lead.nao_contatar?
        return { ok: false, reason: 'já existe um compromisso ativo para este lead' } if ESTADOS_COM_COMPROMISSO_ATIVO.include?(lead.agendamento_status)

        lead.with_lock do
          next if lead.agendamento_status_em_andamento?

          lead.update!(agendamento_status: 'em_andamento')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'agendamento_iniciado', source: 'lavinia',
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
