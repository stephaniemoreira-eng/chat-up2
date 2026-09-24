require 'rails_helper'

RSpec.describe UpSales::AgentTenant do
  let(:account) { create(:account) }
  # A inbox do dispatcher precisa ser WhatsApp da própria conta (CP-07, P1-027-02).
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }

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

    it 'e verdadeiro com whatsapp_inbox e slot sdr habilitado com agente configurado' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '77')

      expect(agent_tenant.dispatcher_ready?).to be(true)
    end

    it 'ignora um slot de outro tipo (follow_up/secretary), so o sdr conta pro dispatcher' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      create(:up_sales_agent_slot, account: account, agent_type: 'follow_up', up2_agents_agent_id: '99')

      expect(agent_tenant.dispatcher_ready?).to be(false)
    end

    # CP-07 -- P1-027-01: desativar o SDR preserva o id remoto no slot; "tem id" não é "está ativo".
    it 'e falso com o slot sdr desabilitado mesmo mantendo o up2_agents_agent_id' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      create(:up_sales_agent_slot, account: account, enabled: false, up2_agents_agent_id: '77')

      expect(agent_tenant.dispatcher_ready?).to be(false)
    end

    it 'volta a ficar pronto ao reabilitar o mesmo slot, sem vinculo paralelo' do
      agent_tenant = create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
      slot = create(:up_sales_agent_slot, account: account, enabled: false, up2_agents_agent_id: '77')

      slot.update!(enabled: true)

      expect(agent_tenant.dispatcher_ready?).to be(true)
      expect(agent_tenant.prospecting_agent_up2_id).to eq('77')
    end

    it 'e falso se a inbox gravada por fora nao for WhatsApp da mesma conta' do
      agent_tenant = create(:up_sales_agent_tenant, account: account)
      create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '77')
      agent_tenant.update_column(:whatsapp_inbox_id, create(:inbox, account: account).id) # rubocop:disable Rails/SkipsModelValidations

      expect(agent_tenant.reload.dispatcher_ready?).to be(false)
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

    it 'e nil quando o slot sdr esta desabilitado (a originacao nunca usa um agente desativado)' do
      agent_tenant = create(:up_sales_agent_tenant, account: account)
      create(:up_sales_agent_slot, account: account, enabled: false, up2_agents_agent_id: '123')

      expect(agent_tenant.prospecting_agent_up2_id).to be_nil
    end
  end

  # CP-07 -- P1-027-02: a regra vive no backend, não só no dropdown.
  describe 'validacao de whatsapp_inbox_id' do
    let(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }

    it 'aceita inbox WhatsApp da mesma conta' do
      expect(agent_tenant.update(whatsapp_inbox_id: inbox.id)).to be(true)
    end

    it 'rejeita inbox nao-WhatsApp da mesma conta' do
      expect(agent_tenant.update(whatsapp_inbox_id: create(:inbox, account: account).id)).to be(false)
      expect(agent_tenant.errors[:whatsapp_inbox_id]).to include('não é uma inbox WhatsApp')
    end

    it 'rejeita inbox WhatsApp de outra conta' do
      other = create(:channel_whatsapp, account: create(:account), sync_templates: false, validate_provider_config: false).inbox

      expect(agent_tenant.update(whatsapp_inbox_id: other.id)).to be(false)
      expect(agent_tenant.errors[:whatsapp_inbox_id]).to include('pertence a outra conta')
    end

    it 'rejeita id inexistente de forma explicita' do
      expect(agent_tenant.update(whatsapp_inbox_id: 0)).to be(false)
      expect(agent_tenant.errors[:whatsapp_inbox_id]).to include('não existe')
    end

    it 'aceita limpar a inbox' do
      agent_tenant.update!(whatsapp_inbox_id: inbox.id)

      expect(agent_tenant.update(whatsapp_inbox_id: nil)).to be(true)
    end
  end

  # CP-16A -- P2-VAL-16 (decisão da Stéphanie em 24/09/2026: responsável Comercial do handoff =
  # Danilo, configurado por conta) e P2-VAL-17 (texto do e-mail de recovery ajustável).
  describe 'configuração de negócio por conta (CP-16A)' do
    let(:account) { create(:account) }
    let(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }

    it 'aceita como responsável Comercial um usuário da própria conta' do
      danilo = create(:user, account: account)

      expect(agent_tenant.update(commercial_responsible_user_id: danilo.id)).to be(true)
      expect(agent_tenant.commercial_responsible_user_id_for_handoff).to eq(danilo.id)
    end

    it 'rejeita usuário de outra conta' do
      outro = create(:user, account: create(:account))

      expect(agent_tenant.update(commercial_responsible_user_id: outro.id)).to be(false)
      expect(agent_tenant.errors[:commercial_responsible_user_id]).to include('não é um usuário desta conta')
    end

    it 'usuário removido da conta depois de configurado deixa de ser responsável (volta a pendente)' do
      danilo = create(:user, account: account)
      agent_tenant.update!(commercial_responsible_user_id: danilo.id)
      AccountUser.where(account: account, user: danilo).destroy_all

      expect(agent_tenant.reload.commercial_responsible_user_id_for_handoff).to be_nil
    end

    it 'aceita os placeholders documentados no e-mail de recovery' do
      expect(agent_tenant.update(recovery_email_subject: '{{marca}} -- {{ nome }}',
                                 recovery_email_body: 'Oi {{nome}}, da {{empresa}}. {{persona}}')).to be(true)
    end

    it 'rejeita placeholder desconhecido' do
      expect(agent_tenant.update(recovery_email_body: 'Oi {{email}} {{nome}}')).to be(false)
      expect(agent_tenant.errors[:recovery_email_body].join).to include('{{email}}')
    end
  end
end
