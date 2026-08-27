# == Schema Information
#
# Table name: sales_prospecting_searches
#
#  id                :bigint           not null, primary key
#  business_type     :string           not null
#  city              :string           not null
#  desired_count     :integer          default(20), not null
#  exclude_keywords  :string
#  min_rating        :decimal(2, 1)
#  min_reviews       :integer
#  neighborhood      :string
#  notes             :text
#  require_phone     :boolean          default(FALSE), not null
#  require_website   :boolean          default(FALSE), not null
#  state             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  user_id           :bigint
#
# Indexes
#
#  index_sales_prospecting_searches_on_account_id  (account_id)
#
class Sales::ProspectingSearch < ApplicationRecord
  self.table_name = 'sales_prospecting_searches'

  belongs_to :account
  belongs_to :user, optional: true

  has_many :results, class_name: 'Sales::ProspectingResult', foreign_key: :sales_prospecting_search_id,
                      dependent: :destroy, inverse_of: :search

  validates :business_type, presence: true
  validates :city, presence: true
  validates :state, presence: true

  def exclude_keyword_list
    exclude_keywords.to_s.split(',').map(&:strip).reject(&:blank?)
  end
end
