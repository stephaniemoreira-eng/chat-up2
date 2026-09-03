require 'rails_helper'

RSpec.describe Sales::ProspectingConfig do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:business_type) }
    it { is_expected.to validate_presence_of(:city) }
    it { is_expected.to validate_presence_of(:state) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:pipeline).class_name('Sales::Pipeline') }
    it { is_expected.to belong_to(:stage).class_name('Sales::Stage').optional }
  end

  describe '.active' do
    it 'returns only configs with active: true' do
      active = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline)
      account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline, active: false)

      expect(described_class.active).to eq([active])
    end
  end
end
