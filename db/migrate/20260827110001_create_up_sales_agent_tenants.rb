class CreateUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    create_table :up_sales_agent_tenants do |t|
      t.bigint :account_id, null: false
      t.string :agents_tenant_id, null: false
      t.string :agents_tenant_slug
      t.string :api_key, null: false

      t.timestamps
    end

    add_index :up_sales_agent_tenants, :account_id, unique: true
  end
end
