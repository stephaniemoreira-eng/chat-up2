# CP-12 (P1-VAL-10; RISK-020-01 confirmado no teste. em 24/09/2026; SSOT §29.1/§30). O chat-up2 só
# VERIFICA a engine_api_key que o up2-agents apresenta -- nunca precisa lê-la de volta (a cópia
# legível fica no Vault do up2-agents, criptografada lá). Então ela deixa de ser guardada aqui:
# fica só o SHA-256. A coluna antiga (`engine_api_key`) continua existindo nesta migration apenas
# como transição -- a rotação (rake up_sales:generate_engine_api_key) grava o digest e a zera; ela
# é removida numa migration posterior, depois da rotação em todos os ambientes.
class AddEngineApiKeyDigestToUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    add_column :up_sales_agent_tenants, :engine_api_key_digest, :string
    add_index :up_sales_agent_tenants, :engine_api_key_digest, unique: true
  end
end
