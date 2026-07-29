class CreateSalesLeads < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :sales_leads do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :sales_pipeline_id, null: false
      t.bigint :sales_stage_id, null: false
      t.bigint :assignee_id
      t.string :title, null: false
      t.string :source
      t.decimal :value, precision: 14, scale: 2
      t.integer :probability
      t.integer :status, null: false, default: 0
      t.date :expected_close_date
      t.datetime :closed_at
      t.datetime :stage_changed_at
      t.datetime :last_activity_at
      # No DB default: Sales::Lead#assign_position always sets this before create, appending to
      # the end of the stage's leads. Decimal (not integer), so a future drag-and-drop reorder can
      # insert at the midpoint between neighbours without renumbering the whole column.
      t.decimal :position, precision: 20, scale: 10, null: false
      t.text :notes
      t.jsonb :custom_attributes, null: false, default: {}
      t.jsonb :additional_attributes, null: false, default: {}

      t.timestamps
    end

    add_index :sales_leads, :account_id
    add_index :sales_leads, :contact_id
    add_index :sales_leads, :assignee_id
    add_index :sales_leads, [:account_id, :sales_pipeline_id, :sales_stage_id, :position],
              name: 'index_sales_leads_on_account_pipeline_stage_position'
  end
end
