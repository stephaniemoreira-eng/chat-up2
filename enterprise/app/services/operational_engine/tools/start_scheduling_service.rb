# acao_sugerida = iniciar_agendamento (SSOT §12.4, S-4 parte 2). Só marca "começou a negociar
# horário" -- agendamento_status: em_andamento. NUNCA confirma sozinho: confirmado só nasce de um
# calendar_event_id real, via ScheduleMeetingService (S-5/Contrato B), que continua sendo o único
# caminho de conversão de verdade.
#
# CP-01 (P1-018-05): todas as guardas dentro do with_lock -- um callback registrado ou uma reunião
# confirmada enquanto esta ação esperava não é sobrescrito para em_andamento.
#
# CP-04:
# - P1-018-03 (§16.1 "Prospect continua Qualificado"; §13.2/§13.3 rota curta): o pedido explícito
#   de agendar É evidência de qualificação -- se o lead ainda não está Qualificado, a qualificação
#   é persistida no MESMO lock, antes do em_andamento (QualificationService). Um lead encerrado ou
#   julgado não qualificado não é reaberto por aqui: recusa.
# - P1-018-04 (§16.4 callback substituído por reunião): callback pendente NÃO bloqueia a negociação
#   de reunião, mas também não é trocado por em_andamento -- se o Calendar falhar depois, o callback
#   tem que continuar pendente. Só ScheduleMeetingService, com sucesso real do Calendar, o substitui.
module OperationalEngine
  module Tools
    class StartSchedulingService
      ESTADOS_COM_REUNIAO_OU_CONTATO_FEITO = %w[confirmado callback_realizado].freeze

      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        result = lead.with_lock do
          reason = blocked_reason(lead)
          next { ok: false, reason: reason } if reason
          next { ok: true, callback_pendente: true } if lead.agendamento_status_callback_registrado?
          next { ok: true } if lead.agendamento_status_em_andamento? && lead.qualificacao_status_qualificado?

          OperationalEngine::QualificationService.qualificar!(lead, source: 'lavinia')
          start_scheduling!(lead)
          { ok: true }
        end
        return result unless result[:ok]

        OperationalEngine::SalesProjectionSync.call(lead)
        OperationalEngine::ComercialProjectionSync.call(lead)
        result
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end

      private

      def blocked_reason(lead)
        reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead, nao_contatar: true)
        return reason if reason
        return 'já existe um compromisso ativo para este lead' if ESTADOS_COM_REUNIAO_OU_CONTATO_FEITO.include?(lead.agendamento_status)
        return 'lead encerrado' if lead.lead_status_encerrado?

        'lead não qualificado' if lead.qualificacao_status_nao_qualificado?
      end

      def start_scheduling!(lead)
        return if lead.agendamento_status_em_andamento?

        lead.update!(agendamento_status: 'em_andamento')
        OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'agendamento_iniciado', source: 'lavinia',
                                              metadata: { correlation_id: SecureRandom.uuid })
      end
    end
  end
end
