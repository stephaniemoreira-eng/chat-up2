require 'rails_helper'

RSpec.describe Sales::Prospecting::ScanResultJob do
  let(:account) { create(:account) }
  let(:search) { account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP') }
  let(:result) { search.results.create!(account: account, place_id: 'p1', name: 'Clinica X') }

  it 'runs the scan for the given result' do
    expect(Sales::Prospecting::ScanService).to receive(:call).with(result)

    described_class.perform_now(result.id)
  end

  it 'does nothing when the result no longer exists' do
    expect(Sales::Prospecting::ScanService).not_to receive(:call)

    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
