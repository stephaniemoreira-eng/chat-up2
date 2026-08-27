class CreateSalesProspectingResults < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_prospecting_results do |t|
      t.bigint :sales_prospecting_search_id, null: false
      t.bigint :account_id, null: false
      t.bigint :sales_lead_id
      t.string :place_id, null: false
      t.string :name
      t.string :address
      t.string :phone_number
      t.string :website
      t.decimal :rating, precision: 2, scale: 1
      t.integer :user_ratings_total

      t.timestamps
    end

    add_index :sales_prospecting_results, :sales_prospecting_search_id, name: 'index_sales_prospecting_results_on_search_id'
    add_index :sales_prospecting_results, :account_id
    add_index :sales_prospecting_results, :place_id
  end
end
