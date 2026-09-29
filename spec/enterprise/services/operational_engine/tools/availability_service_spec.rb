require 'rails_helper'

RSpec.describe OperationalEngine::Tools::AvailabilityService do
  let(:account) { create(:account) }

  around do |example|
    travel_to(Time.zone.parse('2026-09-21 12:00:00')) { example.run }
  end

  def perform(**overrides)
    described_class.new(account: account, time_min: '2026-09-22T00:00:00-03:00', time_max: '2026-09-23T00:00:00-03:00', **overrides).call
  end

  it 'retorna erro quando a conta não tem calendário conectado' do
    result = perform

    expect(result).to eq(ok: false, reason: 'agenda não conectada para esta conta')
  end

  context 'com calendário conectado' do
    let!(:agent_tenant) do
      create(:up_sales_agent_tenant, account: account, calendar_integration_instance_id: 'instance-1')
    end

    it 'devolve os eventos e as faixas livres calculadas pelo Engine' do
      stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events')
        .with(query: hash_including('timeMin' => '2026-09-22T00:00:00-03:00'))
        .to_return(status: 200, body: { events: [{ 'id' => 'evt_1', 'summary' => 'Bloqueado', 'start' => '2026-09-22T14:00:00-03:00', 'end' => '2026-09-22T15:00:00-03:00' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = perform

      expect(result[:ok]).to be(true)
      expect(result[:events]).to eq([{ 'id' => 'evt_1', 'summary' => 'Bloqueado', 'start' => '2026-09-22T14:00:00-03:00', 'end' => '2026-09-22T15:00:00-03:00' }])
      expect(result[:slots]).to include(hash_including(start: '2026-09-22T00:00:00-03:00', end: '2026-09-22T14:00:00-03:00'))
      expect(result[:slots]).to include(hash_including(start: '2026-09-22T15:00:00-03:00', end: '2026-09-23T00:00:00-03:00'))
    end

    it 'falha fechada quando o calendário devolve evento sem intervalo' do
      stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events')
        .to_return(status: 200, body: { events: [{ 'id' => 'evt_1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(perform).to eq(ok: false, reason: 'agenda retornou evento sem intervalo verificável')
    end

    it 'repassa o erro quando o up2-agents falha' do
      stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/events')
        .with(query: hash_including('timeMin' => '2026-09-22T00:00:00-03:00'))
        .to_return(status: 500, body: { error: 'Google indisponível' }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = perform

      expect(result).to eq(ok: false, reason: 'Google indisponível')
    end
  end
end
