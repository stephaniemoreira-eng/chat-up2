# CP-13 (P1-VAL-12; SSOT §15.6-§15.8, §23.2, §28.4, §28.23, §28.25, §28.40): as regras 5 e 6 do
# OutboundSendGate para posts PROGRAMADOS do up2-agents (carimbo content_attributes.up2_automation
# = { kind, job_id, created_at } -- contrato do CP-06). Chamado pelo gate já dentro do lock do lead,
# depois das regras de atendimento humano (1) e de timer anterior à mudança de modo (1b).
#
# Regra 5 -- recovery (kind=RECUPERACAO): o post só sai com a RecoveryActivation desta conversa,
# deste lead, com job_id = activation_id, ainda autorizada, e passando de novo por TODA a
# revalidação do §15.8 (RecoveryEligibility) + ciclo ativo + tentativa esperada + janela de recovery.
# Tentativa já gravada: só balões da mesma mensagem (split), dentro da janela técnica do gate.
#
# Regra 6 -- decisão registrada (follow-up nativo do up2-agents): numa conta com Operational Engine,
# a recovery do SSOT é a ÚNICA automação de reengajamento. Qualquer outro tipo programado fora da
# lista permitida (ENV UP_SALES_ENGINE_AUTOMATION_KINDS, padrão APPOINTMENT_REMINDER -- lembrete de
# reunião real já confirmada, que não é reengajamento) é recusado: FOLLOWUP, REDIRECT_FOLLOWUP,
# REDIRECT_CLOSING e qualquer tipo desconhecido (falha fechado). O up2-agents também desliga o
# gatilho do follow-up nativo para tenants com Engine (PR coordenada) -- esta regra é a autoridade.
module OperationalEngine
  class AutomationSendRules
    def self.allowed_kinds
      ENV.fetch('UP_SALES_ENGINE_AUTOMATION_KINDS', 'APPOINTMENT_REMINDER').split(',').map(&:strip).compact_blank
    end

    def initialize(conversation, stamp)
      @conversation = conversation
      @stamp = stamp || {}
    end

    def recovery?
      @stamp[:kind].to_s == OperationalEngine::RecoveryCycle::AUTOMATION_KIND
    end

    def blocking_reason(lead, recovery)
      return recovery_reason(lead, recovery) if recovery?

      'automacao_fora_do_ciclo_do_engine' unless self.class.allowed_kinds.include?(@stamp[:kind].to_s)
    end

    private

    def recovery_reason(lead, recovery)
      return 'recuperacao_sem_autorizacao' unless authorized_for?(lead, recovery)
      return run_reason(recovery) unless recovery.authorized?

      blockers = OperationalEngine::RecoveryEligibility.blockers(lead, conversation: @conversation, agent_tenant: agent_tenant)
      blockers << 'recuperacao_inativa' unless lead.recuperacao_status_ativa?
      blockers << 'tentativa_divergente' unless lead.tentativa_recuperacao == recovery.tentativa - 1
      blockers << 'fora_da_janela_de_recuperacao' unless OperationalEngine::RecoveryCalendar.within_window?(Time.current)
      blockers.presence&.join(',')
    end

    def authorized_for?(lead, recovery)
      recovery.present? && recovery.canal == 'whatsapp' && recovery.activation_id == @stamp[:job_id].to_s && recovery.lead_id == lead.lead_id
    end

    def run_reason(recovery)
      consumed_at = recovery.status_at
      same_run = recovery.status == 'consumed' && consumed_at.present? && consumed_at >= OperationalEngine::OutboundSendGate.opening_run_window.ago
      return nil if same_run && @conversation.messages.incoming.where('created_at > ?', consumed_at).none?

      'recuperacao_ja_enviada'
    end

    def agent_tenant
      @agent_tenant ||= UpSales::AgentTenant.find_by(account_id: @conversation.account_id)
    end
  end
end
