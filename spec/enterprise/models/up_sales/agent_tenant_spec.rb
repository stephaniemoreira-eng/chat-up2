require 'rails_helper'

RSpec.describe UpSales::AgentTenant do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe '#dispatcher_ready?' do
    it 'e falso sem whatsapp_inbox e sem slot sdr' do
      agent_tenant = create(:up_sales_agent_tenant, account: account)

      expect(agent_tenant.dispatcher_ready?).to be(false)
    end

    it 'e falso com whatsapp_inbox mas sem slot sdr com agente configurado' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)

      expect(agent_tenant.dispatcher_ready?).to be(false)
    end

    it 'e falso com slot sdr mas sem up2_agents_agent_id preenchido (ativado mas ainda sincronizando)' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      create(:up_sales_agent_slot, account: account, up2_agents_agent_id: nil)

      expect(agent_tenant.dispatcher_ready?).to be(false)
    end

    it 'e verdadeiro com whatsapp_inbox e slot sdr com agente configurado' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '77')

      expect(agent_tenant.dispatcher_ready?).to be(true)
    end

    it 'ignora um slot de outro tipo (follow_up/secretary), so o sdr conta pro dispatcher' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      create(:up_sales_agent_slot, account: account, agent_type: 'follow_up', up2_agents_agent_id: '99')

      expect(agent_tenant.dispatcher_ready?).to be(false)
    end
  end

  describe '#prospecting_agent_up2_id' do
    it 'busca o id pelo slot sdr da conta, nao por uma coluna propria' do
      agent_tenant = create(:up_sales_agent_tenant, account: account)
      create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '123')

      expect(agent_tenant.prospecting_agent_up2_id).to eq('123')
    end

    it 'e nil quando nao ha slot sdr' do
      agent_tenant = create(:up_sales_agent_tenant, account: account)

      expect(agent_tenant.prospecting_agent_up2_id).to be_nil
    end
  end
end
