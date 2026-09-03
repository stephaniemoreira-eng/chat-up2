require 'rails_helper'

RSpec.describe Sales::Prospecting::RunConfigService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:stage) { create(:sales_stage, pipeline: pipeline) }
  let(:config) do
    account.sales_prospecting_configs.create!(
      business_type: 'clinica estetica', city: 'Santos', state: 'SP', pipeline: pipeline, stage: stage
    )
  end

  def stub_places_search(places)
    allow(Sales::Prospecting::GooglePlacesSearchService).to receive(:search).and_return(places)
  end

  describe '.call' do
    it 'creates a lead for a new result and stamps last_run_at' do
      stub_places_search([{ place_id: 'p1', name: 'Clinica X', phone_number: '+5513999999999', address: 'Rua X' }])

      expect { described_class.call(config) }.to change(Sales::Lead, :count).by(1)
      expect(config.reload.last_run_at).to be_present
    end

    it 'skips creating a duplicate lead for a place already turned into a lead in a previous run' do
      previous_search = account.sales_prospecting_searches.create!(business_type: 'x', city: 'Santos', state: 'SP')
      existing_lead = create(:sales_lead, account: account, pipeline: pipeline, stage: stage)
      previous_search.results.create!(account: account, place_id: 'p1', name: 'Clinica X (ja e lead)', lead: existing_lead)

      stub_places_search([{ place_id: 'p1', name: 'Clinica X', phone_number: '+5513999999999', address: 'Rua X' }])

      expect { described_class.call(config) }.not_to change(Sales::Lead, :count)
    end

    it 'still creates a lead for a place seen before but never turned into a lead' do
      previous_search = account.sales_prospecting_searches.create!(business_type: 'x', city: 'Santos', state: 'SP')
      previous_search.results.create!(account: account, place_id: 'p1', name: 'Clinica X (sem lead ainda)')

      stub_places_search([{ place_id: 'p1', name: 'Clinica X', phone_number: '+5513999999999', address: 'Rua X' }])

      expect { described_class.call(config) }.to change(Sales::Lead, :count).by(1)
    end

    it 'does not create any lead when the search returns nothing' do
      stub_places_search([])

      expect { described_class.call(config) }.not_to change(Sales::Lead, :count)
      expect(config.reload.last_run_at).to be_present
    end
  end
end
