# Roda de 5 em 5 minutos (ver config/schedule.yml) as buscas automaticas salvas (Sales::
# ProspectingConfig) cujo scheduled_hour+scheduled_minute batem com o instante atual (UTC) --
# mesmo padrao do Follow-up (Sales::FollowUp::SyncJob): itera as configs do instante, cada uma
# roda sua propria busca e falha isoladamente pra nao derrubar as outras. Ver
# docs/fork/ADR-0004-up-sales-reskin.md e 12-saas-prospeccao-multicliente.md (item 1).
#
# Antes disso todas as contas rodavam junto, sempre as 06:00 -- com varios clientes, isso batia a
# API do Google Places pra todo mundo no mesmo minuto. scheduled_hour/scheduled_minute deixam cada
# conta escolher seu proprio horario, com granularidade de 5 minutos (288 janelas por dia).
class Sales::Prospecting::AutoSearchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    now = Time.now.utc
    current_minute = (now.min / 5) * 5

    Sales::ProspectingConfig.active.where(scheduled_hour: now.hour, scheduled_minute: current_minute).find_each do |config|
      Sales::Prospecting::RunConfigService.call(config)
    rescue StandardError => e
      Rails.logger.error("[Sales::Prospecting::AutoSearchJob] config_id=#{config.id} failed: #{e.class}: #{e.message}")
      next
    end
  end
end
