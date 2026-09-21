require 'rails_helper'

RSpec.describe Sales::ProspectingConfig, type: :model do
  let(:account) { create(:account) }
  describe 'validations' do
    it { is_expected.to validate_presence_of(:business_type) }
    it { is_expected.to validate_presence_of(:city) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_inclusion_of(:scheduled_hour).in_range(0..23) }
    it { is_expected.to validate_inclusion_of(:scheduled_minute).in_array([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]) }
  end

  describe 'scheduled_hour' do
    it 'defaults to 6' do
      config = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP')

      expect(config.scheduled_hour).to eq(6)
    end
  end

  describe 'scheduled_minute' do
    it 'defaults to 0' do
      config = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP')

      expect(config.scheduled_minute).to eq(0)
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe '.active' do
    it 'returns only configs with active: true' do
      active = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP')
      account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', active: false)

      expect(described_class.active).to eq([active])
    end
  end
end
