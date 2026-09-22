FactoryBot.define do
  factory :up_sales_agent_slot, class: 'UpSales::AgentSlot' do
    account
    agent_type { 'sdr' }
    enabled { true }
    sequence(:up2_agents_agent_id) { |n| n.to_s }
  end
end
