# Fase 6, peça 2: dispara OperationalEngine::Dispatcher pra cada conta configurada. BacklogCapacity
# já decide quanto pode sair AGORA (janela/teto do dia) -- este job só precisa rodar com frequência
# suficiente pra não deixar capacidade liberada parada por muito tempo; não precisa ele mesmo saber
# de horário comercial.
module OperationalEngine
  class DispatcherJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      # dispatcher_ready? não é mais uma condição só de coluna (o id do agente vem do slot "sdr",
      # UpSales::AgentSlot) -- o where.not aqui é só um pré-filtro barato, a checagem completa é
      # o método do model.
      UpSales::AgentTenant.where.not(whatsapp_inbox_id: nil).find_each do |agent_tenant|
        next unless agent_tenant.dispatcher_ready?

        # CP-02 (P0-019-01): antes de abordar alguém novo, recupera confirmações de envio perdidas --
        # um lead já contatado não pode continuar parecendo Backlog elegível.
        OperationalEngine::OutboundConfirmationReconciler.call(account_id: agent_tenant.account_id)
        OperationalEngine::Dispatcher.call(conta_id: agent_tenant.account_id)
        # CP-13 (P1-VAL-12; SSOT §15.6): Recovery na MESMA fila de saída por inbox, depois da primeira
        # abordagem do tick (o DispatchPacing é compartilhado). Não consome o limite de 20 ativações.
        OperationalEngine::RecoveryDispatcher.call(conta_id: agent_tenant.account_id)
      rescue StandardError => e
        Rails.logger.error("[OperationalEngine::DispatcherJob] account #{agent_tenant.account_id}: #{e.message}")
        ChatwootExceptionTracker.new(e, account: agent_tenant.account).capture_exception
      end
    end
  end
end
