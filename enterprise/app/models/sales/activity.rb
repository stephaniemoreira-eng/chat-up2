# == Schema Information
#
# Table name: sales_activities
#
#  id                    :bigint           not null, primary key
#  activity_type         :integer          not null
#  additional_attributes :jsonb            not null
#  body                  :text
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  sales_lead_id         :bigint           not null
#  user_id               :bigint
#
# Indexes
#
#  index_sales_activities_on_account_id     (account_id)
#  index_sales_activities_on_activity_type  (activity_type)
#  index_sales_activities_on_sales_lead_id  (sales_lead_id)
#
class Sales::Activity < ApplicationRecord
  self.table_name = 'sales_activities'

  belongs_to :account
  belongs_to :lead, class_name: 'Sales::Lead', foreign_key: :sales_lead_id, inverse_of: :activities
  belongs_to :user, optional: true

  enum activity_type: { summary_updated: 0 }

  validates :account_id, presence: true
  validates :activity_type, presence: true

  before_validation :assign_account_from_lead

  scope :ordered, -> { order(created_at: :desc) }

  private

  def assign_account_from_lead
    self.account_id ||= lead&.account_id
  end
end
