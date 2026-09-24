require 'rails_helper'

# CP-07 -- P1-020-01 (segredo no Vault do consumidor, não colado à mão), RISK-020-02 (ordem da
# rotação), RISK-021-02 (credencial ambígua).
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

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FRONTEND_URL').and_return('https://teste.up2aceleradora.com.br/')
  end

  it 'cria a credencial operational_engine no Vault com a chave nova e só depois passa a aceitá-la' do
    stub_vault_list([{ id: '9', kind: 'generic' }])
    create_request = stub_request(:post, vault_url).to_return(status: 200, body: { id: '31' }.to_json, headers: json)
    chave_antiga = agent_tenant.engine_api_key

    result = perform

    agent_tenant.reload
    expect(agent_tenant.engine_api_key).not_to eq(chave_antiga)
    expect(result).to eq(rotated: true, vault_entry_id: '31', account_id: account.id)
    expect(
      create_request.with(
        headers: { 'Authorization' => "Bearer #{agent_tenant.api_key}" },
        body: hash_including(
          'kind' => 'operational_engine', 'baseUrl' => 'https://teste.up2aceleradora.com.br',
          'value' => { 'accountId' => account.id.to_s, 'engineApiKey' => agent_tenant.engine_api_key }
        )
      )
    ).to have_been_made.once
  end

  it 'atualiza a credencial existente em vez de criar outra' do
    stub_vault_list([{ id: '31', kind: 'operational_engine' }])
    update_request = stub_request(:put, "#{vault_url}/31").to_return(status: 200, body: { id: '31' }.to_json, headers: json)

    perform

    expect(update_request.with(body: hash_including('value' => hash_including('engineApiKey' => agent_tenant.reload.engine_api_key))))
      .to have_been_made.once
    expect(a_request(:post, vault_url)).not_to have_been_made
  end

  it 'recusa quando há mais de uma credencial operational_engine (RISK-021-02) e não troca a chave' do
    stub_vault_list([{ id: '31', kind: 'operational_engine' }, { id: '32', kind: 'operational_engine' }])
    chave_antiga = agent_tenant.engine_api_key

    expect { perform }.to raise_error(described_class::ProvisionError, /2 credenciais/)
    expect(agent_tenant.reload.engine_api_key).to eq(chave_antiga)
  end

  it 'Vault recusou: a chave aceita aqui continua a antiga e o erro não carrega segredo' do
    stub_vault_list([])
    stub_request(:post, vault_url).to_return(status: 422, body: { error: 'x' }.to_json, headers: json)
    chave_antiga = agent_tenant.engine_api_key

    expect { perform }.to raise_error(described_class::ProvisionError) { |e| expect(e.message).not_to include(chave_antiga) }
    expect(agent_tenant.reload.engine_api_key).to eq(chave_antiga)
  end

  it 'falha ao gravar aqui depois do Vault: devolve a chave antiga ao Vault (compensação)' do
    stub_vault_list([{ id: '31', kind: 'operational_engine' }])
    stub_request(:put, "#{vault_url}/31").to_return(status: 200, body: { id: '31' }.to_json, headers: json)
    chave_antiga = agent_tenant.engine_api_key
    allow(agent_tenant).to receive(:update!).and_raise(ActiveRecord::RecordNotSaved)

    expect { perform }.to raise_error(ActiveRecord::RecordNotSaved)
    expect(
      a_request(:put, "#{vault_url}/31").with(body: hash_including('value' => hash_including('engineApiKey' => chave_antiga)))
    ).to have_been_made.once
  end

  it 'primeira geração (tenant sem chave) não tenta compensar com chave inexistente' do
    agent_tenant.update_column(:engine_api_key, nil) # rubocop:disable Rails/SkipsModelValidations
    agent_tenant.reload
    stub_vault_list([])
    stub_request(:post, vault_url).to_return(status: 200, body: { id: '31' }.to_json, headers: json)

    expect(perform).to include(rotated: false)
    expect(agent_tenant.reload.engine_api_key).to be_present
  end
end
