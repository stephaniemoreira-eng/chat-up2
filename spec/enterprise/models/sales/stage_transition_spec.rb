require 'rails_helper'

RSpec.describe Sales::StageTransition, type: :model do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline) }
  let(:to_stage) { create(:sales_stage, pipeline: pipeline) }

  describe 'associations' do
    it { is_expected.to belong_to(:lead).class_name('Sales::Lead') }
    it { is_expected.to belong_to(:from_stage).class_name('Sales::Stage').optional }
    it { is_expected.to belong_to(:to_stage).class_name('Sales::Stage') }
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'account assignment' do
    it 'derives account_id from the lead when not set' do
      transition = create(:sales_stage_transition, lead: lead, to_stage: to_stage)
      expect(transition.account_id).to eq(lead.account_id)
    end
  end

  describe 'first transition' do
    it 'allows a blank from_stage' do
      transition = build(:sales_stage_transition, lead: lead, to_stage: to_stage, from_stage: nil)
      expect(transition).to be_valid
    end
  end
end
