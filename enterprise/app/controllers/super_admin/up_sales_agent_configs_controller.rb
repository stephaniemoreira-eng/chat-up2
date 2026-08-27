class SuperAdmin::UpSalesAgentConfigsController < SuperAdmin::EnterpriseBaseController
  before_action :set_account, only: [:show, :update]

  def index
    @accounts = Account.order(:name)
  end

  def show
    @agent_tenant = @account.up_sales_agent_tenant || @account.build_up_sales_agent_tenant
    @slots = current_slots
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
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
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
    permitted = params.require(:agent_tenant).permit(:agents_tenant_id, :agents_tenant_slug, :api_key).to_h
    permitted[:api_key] = nil if permitted[:api_key].blank?
    permitted.compact
  end
end
