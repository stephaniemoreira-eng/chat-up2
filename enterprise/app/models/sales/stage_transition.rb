# == Schema Information
#
# Table name: sales_stage_transitions
#
#  id                                 :bigint           not null, primary key
#  duration_in_previous_stage_seconds :integer
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  account_id                         :bigint           not null
#  from_sales_stage_id                :bigint
#  sales_lead_id                      :bigint           not null
#  to_sales_stage_id                  :bigint           not null
#  user_id                            :bigint
#
# Indexes
#
#  index_sales_stage_transitions_on_account_id         (account_id)
#  index_sales_stage_transitions_on_sales_lead_id      (sales_lead_id)
#  index_sales_stage_transitions_on_to_sales_stage_id  (to_sales_stage_id)
#
class Sales::StageTransition < ApplicationRecord
  self.table_name = 'sales_stage_transitions'

  belongs_to :account
  belongs_to :lead, class_name: 'Sales::Lead', foreign_key: :sales_lead_id, inverse_of: :stage_transitions
  belongs_to :from_stage, class_name: 'Sales::Stage', foreign_key: :from_sales_stage_id, optional: true, inverse_of: false
  belongs_to :to_stage, class_name: 'Sales::Stage', foreign_key: :to_sales_stage_id, inverse_of: false
  belongs_to :user, optional: true

  validates :account_id, presence: true

  before_validation :assign_account_from_lead

  private

  def assign_account_from_lead
    self.account_id ||= lead&.account_id
  end
end
