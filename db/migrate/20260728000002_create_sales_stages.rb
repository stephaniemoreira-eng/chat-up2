class CreateSalesStages < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_stages do |t|
      t.bigint :account_id, null: false
      t.bigint :sales_pipeline_id, null: false
      t.string :name, null: false
      # No DB default: Sales::Stage#assign_position always sets this before create,
      # appending to the end of the pipeline's stages.
      t.integer :position, null: false
      t.string :color
      t.integer :probability
      t.integer :category, null: false, default: 0
      t.integer :stale_after_hours

      t.timestamps
    end

    add_index :sales_stages, :account_id
    add_index :sales_stages, :sales_pipeline_id
    add_index :sales_stages, [:sales_pipeline_id, :position]
  end
end
