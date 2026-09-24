class SuperAdmin::UpSalesAgentConfigsController < SuperAdmin::EnterpriseBaseController
  # CP-16A (P2-VAL-16/P2-VAL-17; decisões da Stéphanie em 24/09/2026): responsável Comercial do
  # handoff e texto do e-mail da 3ª tentativa de recovery, por conta.
  BUSINESS_DECISION_FIELDS = %i[commercial_responsible_user_id recovery_email_subject recovery_email_body].freeze

  before_action :set_account, only: [:show, :update]

  def index
    @accounts = Account.order(:name)
  end

  def show
    @agent_tenant = @account.up_sales_agent_tenant || @account.build_up_sales_agent_tenant
    @slots = current_slots
    @whatsapp_inboxes = whatsapp_inboxes
    @account_users = account_users
  end

  def update
    @agent_tenant = @account.up_sales_agent_tenant || @account.build_up_sales_agent_tenant
    @agent_tenant.assign_attributes(agent_tenant_params)

    if @agent_tenant.save
      sync_errors = update_slots
      if sync_errors.any?
        redirect_to super_admin_account_up_sales_agent_config_path(@account),
                    alert: "Configuração salva, mas houve erro ao sincronizar com o up2-agents: #{sync_errors.join('; ')}"
      else
        redirect_to super_admin_account_up_sales_agent_config_path(@account), notice: 'Configuração salva.'
      end
    else
      @slots = current_slots
      @whatsapp_inboxes = whatsapp_inboxes
      @account_users = account_users
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  # Fase 6 (dispatcher): só inboxes WhatsApp fazem sentido pra originar o primeiro contato --
  # nao lista as outras (email, widget, etc.) que o dispatcher nunca usaria.
  def whatsapp_inboxes
    @account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:name)
  end

  # CP-16A (P2-VAL-16): candidatos a responsável Comercial do handoff -- só usuários desta conta
  # (o modelo revalida; decisão da Stéphanie em 24/09/2026: na Lava e Pronto, o Danilo).
  def account_users
    @account.users.order(:name)
  end

  def current_slots
    UpSales::AgentSlot::AGENT_TYPES.index_with { |type| @account.up_sales_agent_slots.find_or_initialize_by(agent_type: type) }
  end

  def update_slots
    errors = []

    UpSales::AgentSlot::AGENT_TYPES.each do |type|
      slot = @account.up_sales_agent_slots.find_or_initialize_by(agent_type: type)
      slot.enabled = params.dig(:enabled, type).present?
      needs_retry = slot.enabled? && slot.up2_agents_agent_id.blank?
      next unless slot.changed? || needs_retry

      slot.save!
      UpSales::Agents::UpsertAgentService.new(agent_tenant: @agent_tenant, slot: slot).perform
    rescue UpSales::Agents::UpsertAgentService::SyncError => e
      errors << "#{slot.label}: #{e.message}"
    end

    errors
  end

  def agent_tenant_params
    permitted = params.require(:agent_tenant)
                       .permit(:agents_tenant_id, :agents_tenant_slug, :api_key, :calendar_integration_instance_id, :whatsapp_inbox_id,
                               *BUSINESS_DECISION_FIELDS)
                       .to_h
    permitted[:api_key] = nil if permitted[:api_key].blank?
    # compact só tira a api_key em branco (manter a atual). Os campos do CP-16A chegam como "" quando
    # limpos de propósito e são gravados vazios: vazio = responsável pendente / modelo de e-mail padrão.
    BUSINESS_DECISION_FIELDS.each { |field| permitted[field] = permitted[field].presence if permitted.key?(field) }
    permitted.compact.merge(permitted.slice(*BUSINESS_DECISION_FIELDS))
  end
end
