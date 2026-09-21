class CreateSalesPipelines < ActiveRecord::Migration[7.1]
  def change
    # Renamed from 20260728000001 on 2026-09-20 (26c711aeb3) to dodge a timestamp
    # collision with upstream -- any environment that had already migrated under the
    # old name has this table but no schema_migrations row for this new version, so
    # Rails treats it as pending and re-runs it. Guard keeps that a no-op there while
    # still creating the table (and recording the version) on a genuinely fresh DB.
    return if table_exists?(:sales_pipelines)

    create_table :sales_pipelines do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.text :description
      # No DB default: Sales::Pipeline#assign_position always sets this before create,
      # appending to the end of the account's pipelines.
      t.integer :position, null: false
      t.boolean :active, null: false, default: true
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :sales_pipelines, :account_id
    add_index :sales_pipelines, [:account_id, :position]
    add_index :sales_pipelines, :account_id, unique: true, where: 'is_default = true', name: 'index_sales_pipelines_on_account_id_and_default'
  end
end
