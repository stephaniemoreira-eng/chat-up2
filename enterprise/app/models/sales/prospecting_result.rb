# == Schema Information
#
# Table name: sales_prospecting_results
#
#  id                          :bigint           not null, primary key
#  address                     :string
#  name                        :string
#  phone_number                :string
#  place_id                    :string           not null
#  rating                      :decimal(2, 1)
#  user_ratings_total          :integer
#  website                     :string
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  sales_lead_id               :bigint
#  sales_prospecting_search_id :bigint           not null
#
# Indexes
#
#  index_sales_prospecting_results_on_account_id  (account_id)
#  index_sales_prospecting_results_on_place_id    (place_id)
#  index_sales_prospecting_results_on_search_id   (sales_prospecting_search_id)
#
class Sales::ProspectingResult < ApplicationRecord
  self.table_name = 'sales_prospecting_results'

  belongs_to :account
  belongs_to :search, class_name: 'Sales::ProspectingSearch', foreign_key: :sales_prospecting_search_id, inverse_of: :results
  belongs_to :lead, class_name: 'Sales::Lead', foreign_key: :sales_lead_id, optional: true

  validates :place_id, presence: true
end
