require 'rails_helper'

RSpec.describe Sales::Prospecting::AutoSearchJob do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  it 'runs every active config scheduled for the current hour' do
    travel_to Time.utc(2026, 9, 14, 6, 0, 0) do
      config = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline, scheduled_hour: 6)
      account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline, active: false, scheduled_hour: 6)

      expect(Sales::Prospecting::RunConfigService).to receive(:call).with(config)

      described_class.perform_now
    end
  end

  it 'does not run configs scheduled for a different hour' do
    travel_to Time.utc(2026, 9, 14, 6, 0, 0) do
      account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline, scheduled_hour: 8)

      expect(Sales::Prospecting::RunConfigService).not_to receive(:call)

      described_class.perform_now
    end
  end

  it 'runs a config scheduled for a specific 5-minute slot within the hour' do
    travel_to Time.utc(2026, 9, 14, 6, 35, 0) do
      config = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline,
                                                           scheduled_hour: 6, scheduled_minute: 35)

      expect(Sales::Prospecting::RunConfigService).to receive(:call).with(config)

      described_class.perform_now
    end
  end

  it 'does not run configs scheduled for a different 5-minute slot' do
    travel_to Time.utc(2026, 9, 14, 6, 35, 0) do
      account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline,
                                                 scheduled_hour: 6, scheduled_minute: 40)

      expect(Sales::Prospecting::RunConfigService).not_to receive(:call)

      described_class.perform_now
    end
  end

  it 'keeps going when one config blows up' do
    travel_to Time.utc(2026, 9, 14, 6, 0, 0) do
      broken = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline, scheduled_hour: 6)
      healthy = account.sales_prospecting_configs.create!(business_type: 'salao', city: 'Santos', state: 'SP', pipeline: pipeline, scheduled_hour: 6)

      allow(Sales::Prospecting::RunConfigService).to receive(:call).with(broken).and_raise(StandardError, 'boom')
      expect(Sales::Prospecting::RunConfigService).to receive(:call).with(healthy)

      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
