class CreateSalesActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_activities do |t|
      t.bigint :account_id, null: false
      t.bigint :sales_lead_id, null: false
      t.bigint :user_id
      t.integer :activity_type, null: false
      t.text :body
      t.jsonb :additional_attributes, null: false, default: {}

      t.timestamps
    end

    add_index :sales_activities, :account_id
    add_index :sales_activities, :sales_lead_id
    add_index :sales_activities, :activity_type
  end
end
