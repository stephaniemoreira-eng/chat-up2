require 'rails_helper'

RSpec.describe Sales::Prospecting::BioClassifierService do
  before do
    allow(GlobalConfigService).to receive(:load).with('CAPTAIN_OPEN_AI_API_KEY', '').and_return('test-key')
    allow(GlobalConfigService).to receive(:load).with('CAPTAIN_OPEN_AI_ENDPOINT', '').and_return('')
    allow(GlobalConfigService).to receive(:load).with('CAPTAIN_OPEN_AI_MODEL', '').and_return('')
  end

  describe '.call' do
    it 'returns nil without a bio' do
      expect(described_class.call('')).to be_nil
    end

    it 'returns nil without an API key configured' do
      allow(GlobalConfigService).to receive(:load).with('CAPTAIN_OPEN_AI_API_KEY', '').and_return('')

      expect(described_class.call('Somos uma clinica de estetica.')).to be_nil
    end

    it 'parses the two fixed criteria out of the JSON response, never a numeric score' do
      content = { deixa_claro_o_que_a_empresa_faz: true, e_profissional_bem_estruturada: false }.to_json
      response = instance_double(
        HTTParty::Response, success?: true,
                             parsed_response: { 'choices' => [{ 'message' => { 'content' => content } }] }
      )
      allow(HTTParty).to receive(:post).and_return(response)

      result = described_class.call('Somos uma clinica de estetica.')

      expect(result).to eq(clareza: true, profissionalismo: false)
    end

    it 'returns nil when the model returns invalid JSON' do
      response = instance_double(
        HTTParty::Response, success?: true,
                             parsed_response: { 'choices' => [{ 'message' => { 'content' => 'not json' } }] }
      )
      allow(HTTParty).to receive(:post).and_return(response)

      expect(described_class.call('bio')).to be_nil
    end

    it 'returns nil instead of raising on a network error' do
      allow(HTTParty).to receive(:post).and_raise(Net::ReadTimeout)

      expect(described_class.call('bio')).to be_nil
    end
  end
end
