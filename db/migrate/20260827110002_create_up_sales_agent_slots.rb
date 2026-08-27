class CreateUpSalesAgentSlots < ActiveRecord::Migration[7.1]
  def change
    create_table :up_sales_agent_slots do |t|
      t.bigint :account_id, null: false
      t.string :agent_type, null: false
      t.boolean :enabled, null: false, default: false
      t.string :up2_agents_agent_id

      t.timestamps
    end

    add_index :up_sales_agent_slots, [:account_id, :agent_type], unique: true,
                                                                   name: 'index_up_sales_agent_slots_on_account_and_type'
  end
end
