FactoryBot.define do
  factory :up_sales_agent_tenant, class: 'UpSales::AgentTenant' do
    account
    sequence(:agents_tenant_id) { |n| "tenant-#{n}" }
    api_key { SecureRandom.hex(20) }
  end
end
