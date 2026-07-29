class CreateSalesStageTransitions < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_stage_transitions do |t|
      t.bigint :account_id, null: false
      t.bigint :sales_lead_id, null: false
      t.bigint :from_sales_stage_id
      t.bigint :to_sales_stage_id, null: false
      t.bigint :user_id
      t.integer :duration_in_previous_stage_seconds

      t.timestamps
    end

    add_index :sales_stage_transitions, :account_id
    add_index :sales_stage_transitions, :sales_lead_id
    add_index :sales_stage_transitions, :to_sales_stage_id
  end
end
