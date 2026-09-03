class CreateSalesProspectingConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_prospecting_configs do |t|
      t.bigint :account_id, null: false
      t.bigint :sales_pipeline_id, null: false
      t.bigint :sales_stage_id
      t.string :business_type, null: false
      t.string :neighborhood
      t.string :city, null: false
      t.string :state, null: false
      t.integer :desired_count, null: false, default: 20
      t.decimal :min_rating, precision: 2, scale: 1
      t.integer :min_reviews
      t.boolean :require_phone, null: false, default: false
      t.boolean :require_website, null: false, default: false
      t.string :exclude_keywords
      t.boolean :active, null: false, default: true
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :sales_prospecting_configs, :account_id
    add_index :sales_prospecting_configs, %i[account_id active]
  end
end
