require 'rails_helper'

# CP-07 -- P1-020-01 (segredo no Vault do consumidor, não colado à mão), RISK-020-02 (ordem da
# rotação), RISK-021-02 (credencial ambígua). CP-12 -- P1-VAL-10 (aqui fica só o SHA-256).
RSpec.describe UpSales::Agents::ProvisionEngineApiKeyService do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:vault_url) { 'https://agents.up2aceleradora.com.br/api/v1/vault' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_vault_list(entries)
    stub_request(:get, vault_url).to_return(status: 200, body: { entries: entries }.to_json, headers: json)
  end

  def perform
    described_class.new(agent_tenant: agent_tenant).perform
  end

  # A chave que foi enviada ao Vault na última escrita (é a única cópia em claro).
  def key_sent_to_vault(method, url)
    body = nil
    expect(a_request(method, url).with { |req| body = JSON.parse(req.body) }).to have_been_made.at_least_once
    body.dig('value', 'engineApiKey')
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FRONTEND_URL').and_return('https://teste.up2aceleradora.com.br/')
  end

  it 'cria a credencial no Vault com a chave nova e guarda aqui só o digest dela' do
    stub_vault_list([{ id: '9', kind: 'generic' }])
    stub_request(:post, vault_url).to_return(status: 200, body: { id: '31' }.to_json, headers: json)
    digest_antigo = agent_tenant.engine_api_key_digest

    result = perform

    agent_tenant.reload
    nova_chave = key_sent_to_vault(:post, vault_url)
    expect(result).to eq(rotated: true, vault_entry_id: '31', account_id: account.id)
    expect(agent_tenant.engine_api_key_digest).not_to eq(digest_antigo)
    expect(agent_tenant.engine_api_key_digest).to eq(UpSales::AgentTenant.engine_api_key_digest(nova_chave))
    expect(agent_tenant.engine_api_key).to be_nil
    expect(agent_tenant.engine_api_key_matches?(nova_chave)).to be(true)
    expect(
      a_request(:post, vault_url).with(
        headers: { 'Authorization' => "Bearer #{agent_tenant.api_key}" },
        body: hash_including('kind' => 'operational_engine', 'baseUrl' => 'https://teste.up2aceleradora.com.br')
      )
    ).to have_been_made.once
  end

  it 'nenhuma coluna guarda a chave em claro depois da rotação' do
    stub_vault_list([{ id: '31', kind: 'operational_engine' }])
    stub_request(:put, "#{vault_url}/31").to_return(status: 200, body: { id: '31' }.to_json, headers: json)

    perform

    nova_chave = key_sent_to_vault(:put, "#{vault_url}/31")
    valores = UpSales::AgentTenant.connection.select_rows(
      "SELECT * FROM up_sales_agent_tenants WHERE id = #{agent_tenant.id}"
    ).flatten.map(&:to_s)
    expect(valores).not_to include(nova_chave)
    expect(a_request(:post, vault_url)).not_to have_been_made
  end

  it 'recusa quando há mais de uma credencial operational_engine (RISK-021-02) e não troca a chave' do
    stub_vault_list([{ id: '31', kind: 'operational_engine' }, { id: '32', kind: 'operational_engine' }])
    digest_antigo = agent_tenant.engine_api_key_digest

    expect { perform }.to raise_error(described_class::ProvisionError, /2 credenciais/)
    expect(agent_tenant.reload.engine_api_key_digest).to eq(digest_antigo)
  end

  it 'Vault recusou: a transação volta, a chave antiga segue aceita e o erro não carrega segredo' do
    chave_antiga = agent_tenant.issued_engine_api_key
    stub_vault_list([])
    stub_request(:post, vault_url).to_return(status: 422, body: { error: 'x' }.to_json, headers: json)

    expect { perform }.to raise_error(described_class::ProvisionError) { |e| expect(e.message).not_to include(chave_antiga) }
    expect(agent_tenant.reload.engine_api_key_matches?(chave_antiga)).to be(true)
  end

  it 'primeira geração (tenant sem chave nenhuma) informa rotated: false' do
    agent_tenant.update_columns(engine_api_key: nil, engine_api_key_digest: nil) # rubocop:disable Rails/SkipsModelValidations
    agent_tenant.reload
    stub_vault_list([])
    stub_request(:post, vault_url).to_return(status: 200, body: { id: '31' }.to_json, headers: json)

    expect(perform).to include(rotated: false)
    expect(agent_tenant.reload.engine_api_key_digest).to be_present
  end

  describe 'transição da chave legada (tenant ainda não rotacionado)' do
    it 'aceita a chave legada só enquanto não há digest, e a rotação a invalida' do
      agent_tenant.update_columns(engine_api_key: 'chave-legada-em-claro', engine_api_key_digest: nil) # rubocop:disable Rails/SkipsModelValidations
      agent_tenant.reload
      expect(agent_tenant.engine_api_key_matches?('chave-legada-em-claro')).to be(true)

      stub_vault_list([])
      stub_request(:post, vault_url).to_return(status: 200, body: { id: '31' }.to_json, headers: json)
      expect(perform).to include(rotated: true)

      agent_tenant.reload
      expect(agent_tenant.engine_api_key).to be_nil
      expect(agent_tenant.engine_api_key_matches?('chave-legada-em-claro')).to be(false)
    end
  end
end
