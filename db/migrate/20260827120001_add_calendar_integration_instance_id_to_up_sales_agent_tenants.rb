class AddCalendarIntegrationInstanceIdToUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    add_column :up_sales_agent_tenants, :calendar_integration_instance_id, :string
  end
end
