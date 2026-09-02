require 'rails_helper'

RSpec.describe Sales::Prospecting::PlaceDetailsService do
  before do
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_PLACES_API_KEY', '').and_return('test-key')
  end

  describe '.call' do
    it 'returns nil without a place_id' do
      expect(described_class.call(nil)).to be_nil
    end

    it 'extracts the fields used by the Maps pillar' do
      response = instance_double(
        HTTParty::Response, success?: true,
                             parsed_response: {
                               'businessStatus' => 'OPERATIONAL', 'primaryType' => 'beauty_salon',
                               'regularOpeningHours' => { 'periods' => [] }, 'websiteUri' => 'https://x.com',
                               'nationalPhoneNumber' => '(13) 3222-1234', 'rating' => 4.5, 'userRatingCount' => 25
                             }
      )
      allow(HTTParty).to receive(:get).and_return(response)

      result = described_class.call('p1')

      expect(result).to eq(
        business_status: 'OPERATIONAL', primary_type: 'beauty_salon', has_opening_hours: true,
        has_website: true, has_phone: true, rating: 4.5, user_ratings_total: 25
      )
    end

    it 'returns nil when the place is no longer found' do
      response = instance_double(HTTParty::Response, success?: false)
      allow(HTTParty).to receive(:get).and_return(response)

      expect(described_class.call('invalid-id')).to be_nil
    end

    it 'returns nil instead of raising on a network error' do
      allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)

      expect(described_class.call('p1')).to be_nil
    end
  end
end
