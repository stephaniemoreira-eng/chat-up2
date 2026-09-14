# Roda de hora em hora (ver config/schedule.yml) as buscas automaticas salvas (Sales::
# ProspectingConfig) cujo scheduled_hour bate com a hora atual (UTC) -- mesmo padrao do Follow-up
# (Sales::FollowUp::SyncJob): itera as configs da hora, cada uma roda sua propria busca e falha
# isoladamente pra nao derrubar as outras. Ver docs/fork/ADR-0004-up-sales-reskin.md e
# 12-saas-prospeccao-multicliente.md (item 1).
#
# Antes disso todas as contas rodavam junto, sempre as 06:00 -- com varios clientes, isso batia a
# API do Google Places pra todo mundo no mesmo minuto. scheduled_hour deixa cada conta escolher
# seu proprio horario.
class Sales::Prospecting::AutoSearchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Sales::ProspectingConfig.active.where(scheduled_hour: Time.now.utc.hour).find_each do |config|
      Sales::Prospecting::RunConfigService.call(config)
    rescue StandardError => e
      Rails.logger.error("[Sales::Prospecting::AutoSearchJob] config_id=#{config.id} failed: #{e.class}: #{e.message}")
      next
    end
  end
end
