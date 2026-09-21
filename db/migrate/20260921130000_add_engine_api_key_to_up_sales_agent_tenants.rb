# S-5 (plano do Marco 1): sentido inverso do api_key existente -- este é o segredo que o
# up2-agents apresenta quando CHAMA o chat-up2 (rotas operational_engine/tools/*), não o que o
# chat-up2 usa para chamar o up2-agents. Nullable de propósito: tenants existentes ganham o valor
# via has_secure_token (regenerate_engine_api_key!) num passo manual único, não nesta migration.
class AddEngineApiKeyToUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    add_column :up_sales_agent_tenants, :engine_api_key, :string
  end
end
