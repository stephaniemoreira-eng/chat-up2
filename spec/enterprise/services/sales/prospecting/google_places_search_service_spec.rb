require 'rails_helper'

RSpec.describe Sales::Prospecting::GooglePlacesSearchService do
  before do
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_PLACES_API_KEY', '').and_return('test-key')
  end

  def stub_places_response(places)
    response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'places' => places })
    allow(HTTParty).to receive(:post).and_return(response)
  end

  describe '.search' do
    it 'raises when no API key is configured' do
      allow(GlobalConfigService).to receive(:load).with('GOOGLE_PLACES_API_KEY', '').and_return('')

      expect { described_class.search('clinica em Santos, SP') }.to raise_error(described_class::MissingApiKeyError)
    end

    it 'normalizes a punctuated international phone number to E.164' do
      stub_places_response([{ 'id' => 'p1', 'displayName' => { 'text' => 'Clinica X' },
                               'internationalPhoneNumber' => '+55 13 3222-1234' }])

      results = described_class.search('clinica em Santos, SP')

      expect(results.first[:phone_number]).to eq('+551332221234')
    end

    it 'drops the phone number when only a country-code-less nationalPhoneNumber is available' do
      stub_places_response([{ 'id' => 'p1', 'displayName' => { 'text' => 'Clinica X' },
                               'nationalPhoneNumber' => '(13) 3222-1234' }])

      results = described_class.search('clinica em Santos, SP')

      expect(results.first[:phone_number]).to be_nil
    end

    it 'drops the phone number when it is missing entirely' do
      stub_places_response([{ 'id' => 'p1', 'displayName' => { 'text' => 'Clinica X' } }])

      results = described_class.search('clinica em Santos, SP')

      expect(results.first[:phone_number]).to be_nil
    end
  end
end
