# Varredura periodica do Follow-up (Up Sales): promove contatos recem-marcados com a label de
# Follow-up a Sales::Lead e distribui entre o time de vendedores. Ver
# Sales::FollowUp::SyncService e docs/fork/ADR-0004-up-sales-reskin.md.
class Sales::FollowUp::SyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_in_batches do |accounts|
      accounts.each do |account|
        next unless account.feature_enabled?('sales_pipeline')
        next if account.follow_up_pipeline_id.blank? || account.follow_up_team_id.blank?

        Sales::FollowUp::SyncService.perform(account: account)
      rescue Sales::FollowUp::SyncService::NotConfiguredError
        next
      rescue StandardError => e
        # A single misconfigured account (e.g. its Follow-up pipeline was emptied of stages, see
        # Sales::Stage's destroy guard) must never take down the sync for every other account.
        Rails.logger.error(
          "[Sales::FollowUp::SyncJob] account_id=#{account.id} failed: #{e.class}: #{e.message}"
        )
        next
      end
    end
  end
end
