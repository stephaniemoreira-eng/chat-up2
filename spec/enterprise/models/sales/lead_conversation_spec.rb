require 'rails_helper'

RSpec.describe Sales::LeadConversation, type: :model do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline) }
  let(:conversation) { create(:conversation, account: account) }

  describe 'validations' do
    it 'is unique per conversation' do
      create(:sales_lead_conversation, lead: lead, conversation: conversation)
      duplicate = build(:sales_lead_conversation,
                        lead: create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline),
                        conversation: conversation)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation_id]).to be_present
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:lead).class_name('Sales::Lead') }
    it { is_expected.to belong_to(:conversation) }
  end

  describe 'account assignment' do
    it 'derives account_id from the lead when not set' do
      lead_conversation = create(:sales_lead_conversation, lead: lead, conversation: conversation)
      expect(lead_conversation.account_id).to eq(lead.account_id)
    end
  end
end
