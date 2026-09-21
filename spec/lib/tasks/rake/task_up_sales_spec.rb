require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  describe 'up_sales:generate_engine_api_key' do
    let(:account) { create(:account) }

    def run(*)
      task = Rake::Task['up_sales:generate_engine_api_key']
      task.reenable
      task.invoke(*)
    end

    it 'gera a chave quando o tenant ainda não tem uma (coluna adicionada depois de o tenant existir)' do
      tenant = create(:up_sales_agent_tenant, account: account)
      tenant.update_column(:engine_api_key, nil) # rubocop:disable Rails/SkipsModelValidations

      expect { run(account.id.to_s) }.to output(/Gerada.*engine_api_key:.*Cole esta chave/m).to_stdout
      expect(tenant.reload.engine_api_key).to be_present
    end

    it 'rotaciona e avisa quando já existe uma chave' do
      tenant = create(:up_sales_agent_tenant, account: account)
      chave_antiga = tenant.engine_api_key

      expect { run(account.id.to_s) }.to output(/Rotacionada.*ATENÇÃO/m).to_stdout
      expect(tenant.reload.engine_api_key).to be_present
      expect(tenant.engine_api_key).not_to eq(chave_antiga)
    end

    it 'sai com erro quando a conta não tem UpSales::AgentTenant' do
      expect { run(account.id.to_s) }.to raise_error(SystemExit)
    end

    it 'sai com erro sem account_id' do
      expect { run }.to raise_error(SystemExit)
    end
  end
end
