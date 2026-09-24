# S-5 / Contrato B / SSOT §16: registra que um callback foi COMBINADO -- não que foi realizado
# (isso é ação humana separada, fora do escopo do S-5, ver §21.2). Explícito no SSOT: "Callback
# registrado não é conversão" -- por isso este serviço nunca toca conversao_em/tipo_conversao.
#
# CP-09 (P1-VAL-04; SSOT §8.2 "Callback", §16.2, §23.1, §23.2, teste 28.16) -- o estado final é o
# do SSOT, completo: Prospect Qualificado + CALLBACK e Comercial Oportunidade + CALLBACK.
# - Prospect Qualificado: pedir a ligação do Comercial é intenção explícita de avançar (§13.2, rota
#   curta) -- se o lead ainda não está Qualificado, a qualificação é persistida no MESMO lock pelo
#   QualificationService (§13.3), exatamente como a rota curta do agendamento (StartSchedulingService).
# - Oportunidade Comercial: OperationalEngine::ComercialOpportunity, o mesmo caminho do handoff
#   (cria só se não havia, nunca rebaixa, evento `oportunidade_criada`). A frente operacional e o
#   modo de atendimento NÃO mudam: callback registrado não é handoff.
# - Guardas dentro do lock (estado relido), como as demais tools da Lavínia: modo humano,
#   não-contatar, lead encerrado, lead julgado não qualificado e reunião já confirmada (sobrescrever
#   `confirmado` por `callback_registrado` apagaria o fato da reunião real; o §16.4 só prevê o
#   caminho inverso).
# - Idempotente pelo estado: callback já registrado com o estado completo é no-op (nenhum evento
#   novo, nenhuma projeção) -- vale também para o chamador sem turn_id (ToolsController, modo prompt).
module OperationalEngine
  module Tools
    class RegisterCallbackService
      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        result = lead.with_lock do
          reason = blocked_reason(lead)
          next { ok: false, reason: reason } if reason
          next { ok: true } if already_registered?(lead)

          register!(lead)
          { ok: true }
        end
        return result unless result[:ok]

        OperationalEngine::ProjectionReconciler.flush(lead)
        result
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end

      private

      def blocked_reason(lead)
        reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead, nao_contatar: true)
        return reason if reason
        return OperationalEngine::Tools::LaviniaActionGuard::ENCERRADO if lead.lead_status_encerrado?
        return 'lead não qualificado' if lead.qualificacao_status_nao_qualificado?

        'lead tem uma reunião confirmada' if lead.agendamento_status_confirmado?
      end

      def already_registered?(lead)
        lead.agendamento_status_callback_registrado? && lead.qualificacao_status_qualificado? && lead.etapa_comercial.present?
      end

      def register!(lead)
        OperationalEngine::QualificationService.qualificar!(lead, source: 'lavinia')
        OperationalEngine::ComercialOpportunity.garantir!(lead, source: 'lavinia', motivo: 'callback_registrado')
        unless lead.agendamento_status_callback_registrado?
          lead.update!(agendamento_status: 'callback_registrado')
          OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'callback_registrado', source: 'lavinia',
                                                metadata: { correlation_id: SecureRandom.uuid })
        end
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'callback_registrado')
      end
    end
  end
end
