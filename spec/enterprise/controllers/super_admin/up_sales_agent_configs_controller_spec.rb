require 'rails_helper'

RSpec.describe 'Super Admin Up Sales agent config', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'GET /super_admin/accounts/:account_id/up_sales_agent_config' do
    it 'lista so as inboxes WhatsApp da conta pra escolher o dispatcher' do
      whatsapp_channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      create(:inbox, account: account, name: 'Widget do site') # nao deve aparecer

      get "/super_admin/accounts/#{account.id}/up_sales_agent_config"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(whatsapp_channel.inbox.name)
      expect(response.body).not_to include('Widget do site')
    end
  end

  describe 'PATCH /super_admin/accounts/:account_id/up_sales_agent_config' do
    let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
    let(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }

    it 'grava o whatsapp_inbox_id escolhido' do
      patch "/super_admin/accounts/#{account.id}/up_sales_agent_config",
            params: { agent_tenant: { whatsapp_inbox_id: whatsapp_channel.inbox.id } }

      expect(response).to redirect_to(super_admin_account_up_sales_agent_config_path(account))
      expect(agent_tenant.reload.whatsapp_inbox_id).to eq(whatsapp_channel.inbox.id)
    end

    it 'permite limpar o whatsapp_inbox_id (voltar pra "nenhuma")' do
      agent_tenant.update!(whatsapp_inbox: whatsapp_channel.inbox)

      patch "/super_admin/accounts/#{account.id}/up_sales_agent_config",
            params: { agent_tenant: { whatsapp_inbox_id: '' } }

      expect(agent_tenant.reload.whatsapp_inbox_id).to be_nil
    end

    it 'nao mexe na api_key existente quando o campo de senha fica em branco' do
      patch "/super_admin/accounts/#{account.id}/up_sales_agent_config",
            params: { agent_tenant: { whatsapp_inbox_id: whatsapp_channel.inbox.id, api_key: '' } }

      expect(agent_tenant.reload.api_key).to be_present
    end

    it 'mostra o dispatcher como pronto quando inbox e slot sdr estao configurados' do
      agent_tenant.update!(whatsapp_inbox: whatsapp_channel.inbox)
      create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '77')

      get "/super_admin/accounts/#{account.id}/up_sales_agent_config"

      expect(response.body).to include('pronto')
    end
  end
end
