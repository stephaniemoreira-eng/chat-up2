# == Schema Information
#
# Table name: sales_lead_conversations
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  sales_lead_id   :bigint           not null
#
# Indexes
#
#  index_sales_lead_conversations_on_account_id       (account_id)
#  index_sales_lead_conversations_on_conversation_id  (conversation_id) UNIQUE
#  index_sales_lead_conversations_on_sales_lead_id    (sales_lead_id)
#
class Sales::LeadConversation < ApplicationRecord
  self.table_name = 'sales_lead_conversations'

  belongs_to :account
  belongs_to :lead, class_name: 'Sales::Lead', foreign_key: :sales_lead_id, inverse_of: :lead_conversations
  belongs_to :conversation, inverse_of: :sales_lead_conversation

  validates :conversation_id, uniqueness: true

  before_validation :assign_account_from_lead

  private

  def assign_account_from_lead
    self.account_id ||= lead&.account_id
  end
end
