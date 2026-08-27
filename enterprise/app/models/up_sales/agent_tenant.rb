# == Schema Information
#
# Table name: up_sales_agent_tenants
#
#  id                 :bigint           not null, primary key
#  agents_tenant_id   :string           not null
#  agents_tenant_slug :string
#  api_key            :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  index_up_sales_agent_tenants_on_account_id  (account_id) UNIQUE
#
# Liga uma conta Chatwoot ao tenant correspondente no up2-agents. A API do up2-agents não tem
# chave de plataforma entre tenants (verificado): cada conta precisa da própria chave, criada
# manualmente uma vez no painel up2-agents daquele tenant e colada aqui. Ver
# docs/fork/ADR-0004-up-sales-reskin.md (Super Admin de configuração de agente).
class UpSales::AgentTenant < ApplicationRecord
  self.table_name = 'up_sales_agent_tenants'

  belongs_to :account

  encrypts :api_key if Chatwoot.encryption_configured?

  validates :account_id, presence: true, uniqueness: true
  validates :agents_tenant_id, presence: true
  validates :api_key, presence: true
end
