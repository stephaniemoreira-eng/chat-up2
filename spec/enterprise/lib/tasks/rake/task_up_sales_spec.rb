require 'rake'
require 'rails_helper'

# CP-07 (P1-020-01/P2-020-01): a task provisiona a chave no Vault do up2-agents e NUNCA a imprime.
RSpec.describe Rake::Task do
  describe 'up_sales:generate_engine_api_key' do
    let(:account) { create(:account) }
    let(:vault_url) { 'https://agents.up2aceleradora.com.br/api/v1/vault' }
    let(:json) { { 'Content-Type' => 'application/json' } }

    def run(*)
      task = Rake::Task['up_sales:generate_engine_api_key']
      task.reenable
      task.invoke(*)
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('FRONTEND_URL').and_return('https://teste.up2aceleradora.com.br')
      stub_request(:get, vault_url).to_return(status: 200, body: { entries: [] }.to_json, headers: json)
      stub_request(:post, vault_url).to_return(status: 200, body: { id: '31' }.to_json, headers: json)
    end

    # A chave em claro só existe no corpo enviado ao Vault (CP-12: aqui fica só o digest).
    def key_sent_to_vault
      body = nil
      expect(a_request(:post, vault_url).with { |req| body = JSON.parse(req.body) }).to have_been_made.at_least_once
      body.dig('value', 'engineApiKey')
    end

    it 'gera a chave, provisiona no Vault, guarda só o digest e não imprime o segredo' do
      tenant = create(:up_sales_agent_tenant, account: account)
      tenant.update_columns(engine_api_key: nil, engine_api_key_digest: nil) # rubocop:disable Rails/SkipsModelValidations

      output = capture_stdout { run(account.id.to_s) }

      tenant.reload
      chave = key_sent_to_vault
      expect(tenant.engine_api_key_digest).to eq(UpSales::AgentTenant.engine_api_key_digest(chave))
      expect(tenant.engine_api_key).to be_nil
      expect(output).to match(/Gerada.*provisionada no Vault/m)
      expect(output).not_to include(chave)
      expect(output).not_to include(tenant.engine_api_key_digest)
    end

    it 'rotaciona sem expor nem a chave nova nem a antiga' do
      tenant = create(:up_sales_agent_tenant, account: account)
      chave_antiga = tenant.issued_engine_api_key

      output = capture_stdout { run(account.id.to_s) }

      tenant.reload
      chave_nova = key_sent_to_vault
      expect(tenant.engine_api_key_matches?(chave_antiga)).to be(false)
      expect(tenant.engine_api_key_matches?(chave_nova)).to be(true)
      expect(output).to match(/Rotacionada/)
      expect(output).not_to include(chave_antiga)
      expect(output).not_to include(chave_nova)
    end

    it 'sai com erro e não altera a chave quando o Vault recusa' do
      tenant = create(:up_sales_agent_tenant, account: account)
      chave_antiga = tenant.issued_engine_api_key
      stub_request(:post, vault_url).to_return(status: 500)

      expect { run(account.id.to_s) }.to raise_error(SystemExit)
      expect(tenant.reload.engine_api_key_matches?(chave_antiga)).to be(true)
    end

    it 'sai com erro quando a conta não tem UpSales::AgentTenant' do
      expect { run(account.id.to_s) }.to raise_error(SystemExit)
    end

    it 'sai com erro sem account_id' do
      expect { run }.to raise_error(SystemExit)
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end
end
