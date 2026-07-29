class CreateSalesLeadConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_lead_conversations do |t|
      t.bigint :account_id, null: false
      t.bigint :sales_lead_id, null: false
      t.bigint :conversation_id, null: false

      t.timestamps
    end

    add_index :sales_lead_conversations, :account_id
    add_index :sales_lead_conversations, :sales_lead_id
    add_index :sales_lead_conversations, :conversation_id, unique: true
  end
end
