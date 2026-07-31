require 'rails_helper'

RSpec.describe Sales::Activity, type: :model do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline) }

  describe 'associations' do
    it { is_expected.to belong_to(:lead).class_name('Sales::Lead') }
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:activity_type) }
  end

  describe 'account assignment' do
    it 'derives account_id from the lead when not set' do
      activity = create(:sales_activity, lead: lead)
      expect(activity.account_id).to eq(lead.account_id)
    end
  end

  describe '.ordered' do
    it 'orders activities by created_at descending' do
      older = create(:sales_activity, lead: lead, created_at: 2.days.ago)
      newer = create(:sales_activity, lead: lead, created_at: 1.day.ago)

      expect(Sales::Activity.ordered).to eq([newer, older])
    end
  end
end
