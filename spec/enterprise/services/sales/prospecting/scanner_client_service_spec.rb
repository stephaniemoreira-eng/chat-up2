require 'rails_helper'

RSpec.describe Sales::Prospecting::ScannerClientService do
  before do
    allow(GlobalConfigService).to receive(:load).with('SCANNER_URL', '').and_return('https://scan.up2aceleradora.com.br')
    allow(GlobalConfigService).to receive(:load).with('SCANNER_TOKEN', '').and_return('test-token')
  end

  describe '.call' do
    it 'returns nil without a website' do
      expect(described_class.call(website: nil, empresa: 'Clinica X')).to be_nil
    end

    it 'returns nil when the scanner is not configured' do
      allow(GlobalConfigService).to receive(:load).with('SCANNER_TOKEN', '').and_return('')

      expect(described_class.call(website: 'https://x.com', empresa: 'Clinica X')).to be_nil
    end

    it 'returns the parsed scan payload on success' do
      payload = { 'site' => { 'has_whatsapp' => true }, 'instagram' => { 'followers' => 100 } }
      response = instance_double(HTTParty::Response, success?: true, parsed_response: payload)
      allow(HTTParty).to receive(:post).and_return(response)

      expect(described_class.call(website: 'https://x.com', empresa: 'Clinica X')).to eq(payload)
    end

    it 'returns nil instead of raising when the scanner is unreachable' do
      allow(HTTParty).to receive(:post).and_raise(Net::ReadTimeout)

      expect(described_class.call(website: 'https://x.com', empresa: 'Clinica X')).to be_nil
    end
  end
end
