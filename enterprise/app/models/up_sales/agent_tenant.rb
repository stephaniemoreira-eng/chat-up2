# == Schema Information
#
# Table name: up_sales_agent_tenants
#
#  id                                :bigint           not null, primary key
#  agents_tenant_id                 :string           not null
#  agents_tenant_slug               :string
#  api_key                          :string           not null
#  calendar_integration_instance_id :string
#  engine_api_key                   :string
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  account_id                       :bigint           not null
#  whatsapp_inbox_id                :bigint
#
# Indexes
#
#  index_up_sales_agent_tenants_on_account_id          (account_id) UNIQUE
#  index_up_sales_agent_tenants_on_whatsapp_inbox_id   (whatsapp_inbox_id)
#
# Liga uma conta Chatwoot ao tenant correspondente no up2-agents. A API do up2-agents não tem
# chave de plataforma entre tenants (verificado): cada conta precisa da própria chave, criada
# manualmente uma vez no painel up2-agents daquele tenant e colada aqui. Ver
# docs/fork/ADR-0004-up-sales-reskin.md (Super Admin de configuração de agente).
#
# `engine_api_key` é o sentido inverso de `api_key` (S-5, plano do Marco 1): o segredo que o
# up2-agents apresenta ao CHAMAR o chat-up2 (rotas operational_engine/tools/*), não o que usamos
# pra chamar ele. Diferente de `api_key` (colado manualmente, gerado no painel do up2-agents),
# este é gerado por nós (has_secure_token) -- quem chama este lado da relação é o dono dela.
#
# `whatsapp_inbox_id` (Fase 6, dispatcher): qual inbox WhatsApp usar pra originar o primeiro
# contato. Configuração manual, não auto-detectada -- este projeto já teve mais de um ambiente/
# inbox ambíguo pra arriscar adivinhar.
#
# O id do Agent de prospecção no up2-agents NÃO mora aqui -- vem de
# `account.up_sales_agent_slots.find_by(agent_type: 'sdr')&.up2_agents_agent_id`, que já existe
# desde o Super Admin de configuração de agente (ver UpSales::Agents::UpsertAgentService).
# Corrigido depois de descobrir esse mecanismo: a Fase 6 (dispatcher) tinha adicionado uma coluna
# `prospecting_agent_id` própria, redundante e sem nenhum jeito real de ser preenchida.
class UpSales::AgentTenant < ApplicationRecord
  self.table_name = 'up_sales_agent_tenants'

  PROSPECTING_AGENT_SLOT_TYPE = 'sdr'.freeze

  belongs_to :account
  belongs_to :whatsapp_inbox, class_name: 'Inbox', optional: true

  has_secure_token :engine_api_key

  encrypts :api_key if Chatwoot.encryption_configured?
  encrypts :engine_api_key if Chatwoot.encryption_configured?

  validates :account_id, presence: true, uniqueness: true
  validates :agents_tenant_id, presence: true
  validates :api_key, presence: true

  # A Fase 6 do dispatcher só é elegível quando as duas peças estão configuradas -- faltando
  # qualquer uma, OperationalEngine::Dispatcher pula a conta inteira (falha explícita, não
  # tenta adivinhar qual inbox/agente usar).
  def dispatcher_ready?
    whatsapp_inbox_id.present? && prospecting_agent_up2_id.present?
  end

  def prospecting_agent_up2_id
    account.up_sales_agent_slots.find_by(agent_type: PROSPECTING_AGENT_SLOT_TYPE)&.up2_agents_agent_id
  end
end
