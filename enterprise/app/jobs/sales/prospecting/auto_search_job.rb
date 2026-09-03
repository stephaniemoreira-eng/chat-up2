# Roda diariamente as buscas automaticas salvas (Sales::ProspectingConfig) -- mesmo padrao do
# Follow-up (Sales::FollowUp::SyncJob): itera as configs ativas, cada uma roda sua propria busca
# e falha isoladamente pra nao derrubar as outras. Ver docs/fork/ADR-0004-up-sales-reskin.md e
# 12-saas-prospeccao-multicliente.md (item 1).
class Sales::Prospecting::AutoSearchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Sales::ProspectingConfig.active.find_each do |config|
      Sales::Prospecting::RunConfigService.call(config)
    rescue StandardError => e
      Rails.logger.error("[Sales::Prospecting::AutoSearchJob] config_id=#{config.id} failed: #{e.class}: #{e.message}")
      next
    end
  end
end
