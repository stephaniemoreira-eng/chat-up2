require 'rails_helper'

RSpec.describe Sales::Prospecting::SearchService do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:params) { { business_type: 'clinica de estetica', city: 'Santos', state: 'SP', desired_count: 5 } }

  describe '#perform' do
    it 'truncates an overlong website instead of raising' do
      long_website = "https://example.com/#{'a' * 300}"
      allow(Sales::Prospecting::GooglePlacesSearchService).to receive(:search).and_return([
                                                                                             { place_id: 'p1', name: 'Clinica X', address: 'Rua X',
                                                                                               phone_number: '11999999999', website: long_website,
                                                                                               rating: 4.5, user_ratings_total: 10 }
                                                                                           ])

      outcome = described_class.perform(account: account, user: user, params: params)

      expect(outcome[:results].size).to eq(1)
      expect(outcome[:results].first.website.length).to eq(255)
      expect(outcome[:results].first.website).to eq(long_website.truncate(255))
    end

    it 'persists results that pass the configured filters' do
      allow(Sales::Prospecting::GooglePlacesSearchService).to receive(:search).and_return([
                                                                                             { place_id: 'p1', name: 'Clinica X', address: 'Rua X',
                                                                                               phone_number: '11999999999', website: 'https://x.com',
                                                                                               rating: 4.5, user_ratings_total: 10 }
                                                                                           ])

      outcome = described_class.perform(account: account, user: user, params: params.merge(min_rating: '4.0'))

      expect(outcome[:results].size).to eq(1)
      expect(outcome[:results].first.place_id).to eq('p1')
    end
  end
end
