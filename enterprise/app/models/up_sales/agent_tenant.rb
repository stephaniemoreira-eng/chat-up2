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
#  recovery_email_body              :text
#  recovery_email_subject           :string
#  account_id                       :bigint           not null
#  commercial_responsible_user_id   :bigint
#  whatsapp_inbox_id                :bigint
#
# Indexes
#
#  index_up_sales_agent_tenants_on_account_id                     (account_id) UNIQUE
#  index_up_sales_agent_tenants_on_commercial_responsible_user_id (commercial_responsible_user_id)
#  index_up_sales_agent_tenants_on_engine_api_key_digest          (engine_api_key_digest) UNIQUE
#  index_up_sales_agent_tenants_on_whatsapp_inbox_id              (whatsapp_inbox_id)
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
#
# CP-16A -- decisões de negócio da Stéphanie em 24/09/2026 (lacunas do SSOT), configuradas aqui:
# - `commercial_responsible_user_id` (P2-VAL-16, "DANILO"): o usuário DESTA conta que vira o
#   responsável Comercial quando a Lavínia faz o handoff e nenhum humano já é responsável (ver
#   OperationalEngine::CommercialResponsibleResolver). Nulo = responsável pendente (comportamento do
#   CP-05). Não há nome/ID fixo no código: cada conta escolhe o seu no Super Admin.
# - `recovery_email_subject` / `recovery_email_body` (P2-VAL-17, "SER AJUSTÁVEL"): texto do e-mail da
#   3ª tentativa de recovery, com os placeholders de OperationalEngine::RecoveryEmailTemplate. Vazios =
#   modelo neutro do CP-13.
class UpSales::AgentTenant < ApplicationRecord
  self.table_name = 'up_sales_agent_tenants'

  PROSPECTING_AGENT_SLOT_TYPE = 'sdr'.freeze

  belongs_to :account
  belongs_to :whatsapp_inbox, class_name: 'Inbox', optional: true
  belongs_to :commercial_responsible_user, class_name: 'User', optional: true

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
  validate :commercial_responsible_user_must_belong_to_account
  validates :recovery_email_subject, length: { maximum: OperationalEngine::RecoveryEmailTemplate::SUBJECT_MAX_LENGTH }
  validates :recovery_email_body, length: { maximum: OperationalEngine::RecoveryEmailTemplate::BODY_MAX_LENGTH }
  validate :recovery_email_placeholders_must_be_known

  # CP-16A (P2-VAL-16): o responsável configurado, só enquanto ele ainda é usuário desta conta. Um
  # usuário removido da conta depois de configurado não vira responsável -- volta a ser "pendente".
  def commercial_responsible_user_id_for_handoff
    return if commercial_responsible_user_id.blank?

    commercial_responsible_user_id if account.users.exists?(id: commercial_responsible_user_id)
  end

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

  def commercial_responsible_user_must_belong_to_account
    return if commercial_responsible_user_id.blank?
    return if account.present? && account.users.exists?(id: commercial_responsible_user_id)

    errors.add(:commercial_responsible_user_id, 'não é um usuário desta conta')
  end

  def recovery_email_placeholders_must_be_known
    { recovery_email_subject: recovery_email_subject, recovery_email_body: recovery_email_body }.each do |field, text|
      unknown = OperationalEngine::RecoveryEmailTemplate.unknown_placeholders(text)
      next if unknown.empty?

      allowed = OperationalEngine::RecoveryEmailTemplate::PLACEHOLDERS.map { |key| "{{#{key}}}" }.join(', ')
      errors.add(field, "tem placeholder desconhecido (#{unknown.map { |key| "{{#{key}}}" }.join(', ')}); use só #{allowed}")
    end
  end

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
