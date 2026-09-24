FactoryBot.define do
  factory :up_sales_agent_tenant, class: 'UpSales::AgentTenant' do
    account
    sequence(:agents_tenant_id) { |n| "tenant-#{n}" }
    api_key { SecureRandom.hex(20) }

    # CP-12: só o digest é persistido; a chave em claro fica em `issued_engine_api_key` (memória).
    after(:build, &:assign_new_engine_api_key)
  end
end
