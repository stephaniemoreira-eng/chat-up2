require 'rails_helper'

RSpec.describe Sales::Prospecting::AutoSearchJob do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  it 'runs every active config' do
    config = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline)
    account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline, active: false)

    expect(Sales::Prospecting::RunConfigService).to receive(:call).with(config)

    described_class.perform_now
  end

  it 'keeps going when one config blows up' do
    broken = account.sales_prospecting_configs.create!(business_type: 'academia', city: 'Santos', state: 'SP', pipeline: pipeline)
    healthy = account.sales_prospecting_configs.create!(business_type: 'salao', city: 'Santos', state: 'SP', pipeline: pipeline)

    allow(Sales::Prospecting::RunConfigService).to receive(:call).with(broken).and_raise(StandardError, 'boom')
    expect(Sales::Prospecting::RunConfigService).to receive(:call).with(healthy)

    expect { described_class.perform_now }.not_to raise_error
  end
end
