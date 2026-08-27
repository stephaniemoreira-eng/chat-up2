module Enterprise::Concerns::Account
  extend ActiveSupport::Concern

  # Fork-owned feature flags, stored in the `settings` jsonb column rather than the
  # config/features.yml bitset columns. Bit positions there are derived from order of
  # appearance, so any addition risks colliding with a flag added independently upstream (or
  # by fazer-ai's own fork) after a merge, silently enabling the wrong feature. This mirrors
  # the fix fazer-ai's own Pro fork already shipped for the identical problem
  # (kanban_enabled/internal_chat_pro_enabled). See docs/fork/ADR-0001-extension-strategy.md.
  FORK_SETTINGS_FEATURES = %w[sales_pipeline sales_kanban].freeze

  included do
    store_accessor :settings, :conversation_required_attributes
    store_accessor :settings, :sales_pipeline_enabled, :sales_kanban_enabled
    # Marca própria por conta (Up Sales) — logo e cor exibidos no lugar da marca genérica do
    # Chatwoot. Ver docs/fork/ADR-0004-up-sales-reskin.md.
    store_accessor :settings, :brand_color, :brand_logo_url

    has_many :sla_policies, dependent: :destroy_async
    has_many :applied_slas, dependent: :destroy_async
    has_many :custom_roles, dependent: :destroy_async
    has_many :agent_capacity_policies, dependent: :destroy_async

    has_many :captain_assistants, dependent: :destroy_async, class_name: 'Captain::Assistant'
    has_many :captain_assistant_responses, dependent: :destroy_async, class_name: 'Captain::AssistantResponse'
    has_many :captain_faq_observations, dependent: :destroy_async, class_name: 'Captain::FaqObservation'
    has_many :captain_faq_suggestions, dependent: :destroy_async, class_name: 'Captain::FaqSuggestion'
    has_many :captain_documents, dependent: :destroy_async, class_name: 'Captain::Document'
    has_many :captain_custom_tools, dependent: :destroy_async, class_name: 'Captain::CustomTool'
    has_many :captain_agent_sessions, dependent: :destroy_async, class_name: 'Captain::AgentSession'

    has_many :copilot_threads, dependent: :destroy_async
    has_many :companies, dependent: :destroy_async
    has_many :calls, dependent: :destroy_async

    # Fork-owned CRM module. See docs/fork/ADR-0002-namespace-sales.md.
    has_many :sales_pipelines, dependent: :destroy_async, class_name: 'Sales::Pipeline'
    has_many :sales_leads, dependent: :destroy_async, class_name: 'Sales::Lead'
    has_many :sales_prospecting_searches, dependent: :destroy_async, class_name: 'Sales::ProspectingSearch'
    has_many :sales_prospecting_results, dependent: :destroy_async, class_name: 'Sales::ProspectingResult'

    # Super Admin de configuração de agente (up2-agents). Ver ADR-0004-up-sales-reskin.md.
    has_one :up_sales_agent_tenant, dependent: :destroy_async, class_name: 'UpSales::AgentTenant'
    has_many :up_sales_agent_slots, dependent: :destroy_async, class_name: 'UpSales::AgentSlot'

    has_one :saml_settings, dependent: :destroy_async, class_name: 'AccountSamlSettings'
  end

  def feature_enabled?(name)
    return !!ActiveModel::Type::Boolean.new.cast(public_send("#{name}_enabled")) if FORK_SETTINGS_FEATURES.include?(name.to_s)

    super
  end

  # Featurable#all_features (and enabled_features/disabled_features, which are derived from it)
  # only walks config/features.yml — the fork's settings-backed flags are deliberately absent
  # from that file, so without this they'd never reach the frontend's `account.features` payload
  # (see app/views/api/v1/models/_account.json.jbuilder), even though feature_enabled? itself
  # already handles them correctly for backend checks.
  def all_features
    super.merge(FORK_SETTINGS_FEATURES.index_with { |name| feature_enabled?(name) })
  end

  def enable_features(*names)
    settings_names, bitmask_names = names.map(&:to_s).partition { |name| FORK_SETTINGS_FEATURES.include?(name) }
    settings_names.each { |name| public_send("#{name}_enabled=", true) }
    super(*bitmask_names)
  end

  def disable_features(*names)
    settings_names, bitmask_names = names.map(&:to_s).partition { |name| FORK_SETTINGS_FEATURES.include?(name) }
    settings_names.each { |name| public_send("#{name}_enabled=", false) }
    super(*bitmask_names)
  end
end
