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
#  engine_api_key_digest            :string
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  account_id                       :bigint           not null
#  whatsapp_inbox_id                :bigint
#
# Indexes
#
#  index_up_sales_agent_tenants_on_account_id          (account_id) UNIQUE
#  index_up_sales_agent_tenants_on_engine_api_key_digest (engine_api_key_digest) UNIQUE
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
# este é gerado por nós -- quem chama este lado da relação é o dono dela.
#
# CP-12 (P1-VAL-10; RISK-020-01): este lado só VERIFICA a chave, nunca precisa lê-la de volta --
# então guardamos só o SHA-256 (`engine_api_key_digest`). A chave em claro existe apenas no Vault do
# up2-agents (criptografada lá) e, por instantes, em memória no objeto que acabou de gerá-la
# (`issued_engine_api_key`, nunca persistido). A coluna `engine_api_key` é legado: aceita só
# enquanto o tenant ainda não foi rotacionado (sem digest), e a rotação a zera.
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

  encrypts :api_key if Chatwoot.encryption_configured?
  encrypts :engine_api_key if Chatwoot.encryption_configured?

  # A chave em claro recém-gerada, só em memória (nunca persistida). Quem a gera entrega ao Vault.
  attr_reader :issued_engine_api_key

  def self.engine_api_key_digest(key)
    OpenSSL::Digest::SHA256.hexdigest(key.to_s)
  end

  # Gera uma chave nova e deixa gravável só o digest (a coluna legada é zerada). Não salva.
  def assign_new_engine_api_key
    @issued_engine_api_key = SecureRandom.base58(32)
    self.engine_api_key_digest = self.class.engine_api_key_digest(@issued_engine_api_key)
    self.engine_api_key = nil
    @issued_engine_api_key
  end

  def engine_api_key_configured?
    engine_api_key_digest.present? || engine_api_key.present?
  end

  # Comparação em tempo constante. Sem digest (tenant ainda não rotacionado), vale a chave legada.
  def engine_api_key_matches?(provided)
    return false if provided.blank?

    if engine_api_key_digest.present?
      ActiveSupport::SecurityUtils.secure_compare(self.class.engine_api_key_digest(provided), engine_api_key_digest)
    else
      engine_api_key.present? && ActiveSupport::SecurityUtils.secure_compare(provided, engine_api_key)
    end
  end

  validates :account_id, presence: true, uniqueness: true
  validates :agents_tenant_id, presence: true
  validates :api_key, presence: true
  validate :whatsapp_inbox_must_be_prospecting_channel

  # A Fase 6 do dispatcher só é elegível quando as duas peças estão configuradas -- faltando
  # qualquer uma, OperationalEngine::Dispatcher pula a conta inteira (falha explícita, não
  # tenta adivinhar qual inbox/agente usar).
  #
  # CP-07 (P1-027-01/P1-027-02): a inbox precisa ser WhatsApp DA MESMA conta (defesa contra linha
  # gravada por outro caminho que não o form) e o agente de prospecção precisa vir de um slot SDR
  # HABILITADO. Desativar o SDR preserva up2_agents_agent_id no slot (UpsertAgentService), então
  # "tem id" não significa "está ativo". A mesma regra vale pra UI, pro DispatcherJob e pra
  # resolução do agent id na originação -- todos passam por aqui.
  def dispatcher_ready?
    valid_prospecting_inbox? && prospecting_agent_up2_id.present?
  end

  def prospecting_agent_up2_id
    slot = account.up_sales_agent_slots.find_by(agent_type: PROSPECTING_AGENT_SLOT_TYPE)
    slot.up2_agents_agent_id.presence if slot&.enabled?
  end

  def valid_prospecting_inbox?
    whatsapp_inbox.present? && whatsapp_inbox.account_id == account_id && whatsapp_inbox.channel_type == 'Channel::Whatsapp'
  end

  private

  def whatsapp_inbox_must_be_prospecting_channel
    return if whatsapp_inbox_id.blank?

    inbox = Inbox.find_by(id: whatsapp_inbox_id)
    if inbox.nil?
      errors.add(:whatsapp_inbox_id, 'não existe')
    elsif inbox.account_id != account_id
      errors.add(:whatsapp_inbox_id, 'pertence a outra conta')
    elsif inbox.channel_type != 'Channel::Whatsapp'
      errors.add(:whatsapp_inbox_id, 'não é uma inbox WhatsApp')
    end
  end
end
