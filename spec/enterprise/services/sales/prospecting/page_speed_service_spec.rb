require 'rails_helper'

RSpec.describe Sales::Prospecting::PageSpeedService do
  before do
    allow(GlobalConfigService).to receive(:load).with('PAGESPEED_API_KEY', '').and_return('test-key')
  end

  describe '.call' do
    it 'returns nil when there is no website' do
      expect(described_class.call(nil)).to be_nil
    end

    it 'returns nil when no API key is configured (falls back to GOOGLE_PLACES_API_KEY)' do
      allow(GlobalConfigService).to receive(:load).with('PAGESPEED_API_KEY', '').and_return('')
      allow(GlobalConfigService).to receive(:load).with('GOOGLE_PLACES_API_KEY', '').and_return('')

      expect(described_class.call('https://example.com')).to be_nil
    end

    it 'extracts the three category scores as 0-100 integers' do
      response = instance_double(
        HTTParty::Response, success?: true,
                             parsed_response: { 'lighthouseResult' => { 'categories' => {
                               'performance' => { 'score' => 0.87 },
                               'seo' => { 'score' => 1.0 },
                               'best-practices' => { 'score' => 0.5 }
                             } } }
      )
      allow(HTTParty).to receive(:get).and_return(response)

      result = described_class.call('https://example.com')

      expect(result).to eq(performance_score: 87, seo_score: 100, best_practices_score: 50)
    end

    it 'returns nil instead of raising when the request fails' do
      allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)

      expect(described_class.call('https://example.com')).to be_nil
    end

    it 'returns nil when the response is not successful' do
      response = instance_double(HTTParty::Response, success?: false)
      allow(HTTParty).to receive(:get).and_return(response)

      expect(described_class.call('https://example.com')).to be_nil
    end
  end
end
