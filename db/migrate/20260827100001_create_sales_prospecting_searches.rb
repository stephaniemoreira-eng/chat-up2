class CreateSalesProspectingSearches < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :sales_prospecting_searches do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
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
      t.text :notes

      t.timestamps
    end

    add_index :sales_prospecting_searches, :account_id
  end
end
