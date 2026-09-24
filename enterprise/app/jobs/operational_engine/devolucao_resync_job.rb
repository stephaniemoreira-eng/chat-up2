# CP-16B (P2-VAL-20; decisão da Stéphanie em 24/09/2026). Executa o turno silencioso de
# ressincronização pós-devolução (OperationalEngine::DevolucaoResync) fora da requisição do "Devolver"
# -- a devolução já está gravada quando este job roda, e nada aqui a desfaz.
#
# Retry limitado e barato (um turno de LLM, sem envio): UP_SALES_DEVOLUCAO_RESYNC_ATTEMPTS tentativas
# no total (padrão 2), espaçadas por UP_SALES_DEVOLUCAO_RESYNC_WAIT_SECONDS (padrão 30). Esgotado:
# log + evento `ressincronizacao_devolucao_falhou` no lead, e o `ultimo_ponto` anterior continua valendo.
module OperationalEngine
  class DevolucaoResyncJob < ApplicationJob
    ATTEMPTS = [ENV.fetch('UP_SALES_DEVOLUCAO_RESYNC_ATTEMPTS', '2').to_i, 1].max
    WAIT = ENV.fetch('UP_SALES_DEVOLUCAO_RESYNC_WAIT_SECONDS', '30').to_i.seconds

    queue_as :default

    retry_on UpSales::Agents::ResyncConversationService::SyncError, wait: WAIT, attempts: ATTEMPTS do |job, error|
      lead_id, devolucao_id = job.arguments
      Rails.logger.error("[OperationalEngine::DevolucaoResyncJob] esgotou tentativas lead=#{lead_id} devolucao=#{devolucao_id}: #{error.message}")
      OperationalEngine::DevolucaoResync.record_failure(lead_id, devolucao_id, error)
    end

    def perform(lead_id, devolucao_id, devolvido_em = nil)
      OperationalEngine::DevolucaoResync.call(lead_id: lead_id, devolucao_id: devolucao_id, devolvido_em: devolvido_em)
    end
  end
end
