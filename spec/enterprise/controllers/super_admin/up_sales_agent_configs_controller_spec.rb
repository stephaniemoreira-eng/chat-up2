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

    # CP-07 -- P1-027-01: SDR desativado nunca aparece como pronto.
    it 'mostra o dispatcher como incompleto quando o slot sdr esta desabilitado' do
      agent_tenant.update!(whatsapp_inbox: whatsapp_channel.inbox)
      create(:up_sales_agent_slot, account: account, enabled: false, up2_agents_agent_id: '77')

      get "/super_admin/accounts/#{account.id}/up_sales_agent_config"

      expect(response.body).to include('incompleto')
      expect(response.body).not_to include('>pronto<')
    end

    # CP-07 -- P1-027-02: request forjado é rejeitado antes de persistir.
    it 'rejeita inbox WhatsApp de outra conta enviada por request forjado' do
      forjada = create(:channel_whatsapp, account: create(:account), sync_templates: false, validate_provider_config: false).inbox

      patch "/super_admin/accounts/#{account.id}/up_sales_agent_config", params: { agent_tenant: { whatsapp_inbox_id: forjada.id } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent_tenant.reload.whatsapp_inbox_id).to be_nil
    end

    it 'rejeita inbox nao-WhatsApp da mesma conta enviada por request forjado' do
      widget = create(:inbox, account: account)

      patch "/super_admin/accounts/#{account.id}/up_sales_agent_config", params: { agent_tenant: { whatsapp_inbox_id: widget.id } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent_tenant.reload.whatsapp_inbox_id).to be_nil
    end
  end

  describe 'PATCH numa conta sem tenant ainda (achado testando ao vivo em teste., 23/09)' do
    let(:account_sem_tenant) { create(:account) }

    it 'mostra as mensagens de erro quando falta um campo obrigatorio (api_key), em vez de falhar em silencio' do
      patch "/super_admin/accounts/#{account_sem_tenant.id}/up_sales_agent_config",
            params: { agent_tenant: { agents_tenant_id: '3', agents_tenant_slug: 'lava-e-pronto' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Não foi possível salvar')

      expected_message = UpSales::AgentTenant.new(agents_tenant_id: '3').tap(&:valid?).errors.full_messages.find { |m| m.match?(/api.?key/i) }
      expect(expected_message).to be_present
      # a view escapa o HTML (o apostrofo de "can't" vira &#39;) -- comparar com o mesmo escape,
      # nao com a string crua da validacao.
      expect(response.body).to include(ERB::Util.html_escape(expected_message))
      expect(account_sem_tenant.reload.up_sales_agent_tenant).to be_nil
    end
  end
end
