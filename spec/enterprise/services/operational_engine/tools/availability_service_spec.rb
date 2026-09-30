require 'rails_helper'

RSpec.describe OperationalEngine::Tools::AvailabilityService do
  let(:account) { create(:account) }

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

    it 'devolve somente slots verificáveis do periodo' do
      stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/availability')
        .with(query: hash_including('timeMin' => '2026-09-22T00:00:00-03:00'))
        .to_return(status: 200, body: { availability: { slots: [{ start: '2026-09-22T14:00:00-03:00', end: '2026-09-22T14:30:00-03:00', label: 'seg 22/09 14:00' }] } }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = perform

      expect(result).to eq(ok: true, slots: [{ 'start' => '2026-09-22T14:00:00-03:00', 'end' => '2026-09-22T14:30:00-03:00', 'label' => 'seg 22/09 14:00' }])
    end

    it 'repassa o erro quando o up2-agents falha' do
      stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/availability')
        .with(query: hash_including('timeMin' => '2026-09-22T00:00:00-03:00'))
        .to_return(status: 500, body: { error: 'Google indisponível' }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = perform

      expect(result).to eq(ok: false, reason: 'Google indisponível')
    end

    it 'recusa uma resposta sem slots verificáveis' do
      stub_request(:get, 'https://agents.up2aceleradora.com.br/api/v1/integrations/instances/instance-1/calendar/availability')
        .to_return(status: 200, body: { availability: { events: [] } }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(perform).to eq(ok: false, reason: 'agenda devolveu disponibilidade inválida')
    end
  end
end
