# == Schema Information
#
# Table name: up_sales_agent_slots
#
#  id                  :bigint           not null, primary key
#  agent_type          :string           not null
#  enabled             :boolean          default(FALSE), not null
#  up2_agents_agent_id :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_up_sales_agent_slots_on_account_and_type  (account_id,agent_type) UNIQUE
#
# Um dos 3 tipos fixos de agente de IA (up2-agents) que a UP2 pode ativar por contrato pra uma
# conta. Ver docs/fork/ADR-0004-up-sales-reskin.md (Super Admin de configuração de agente).
class UpSales::AgentSlot < ApplicationRecord
  self.table_name = 'up_sales_agent_slots'

  AGENT_TYPES = %w[sdr follow_up secretary].freeze
  LABELS = {
    'sdr' => 'Prospecção/SDR',
    'follow_up' => 'Follow-up',
    'secretary' => 'Secretária'
  }.freeze

  belongs_to :account

  validates :agent_type, presence: true, inclusion: { in: AGENT_TYPES }, uniqueness: { scope: :account_id }

  def label
    LABELS.fetch(agent_type)
  end
end
