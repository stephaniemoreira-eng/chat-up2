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
      end
    end
  end
end
