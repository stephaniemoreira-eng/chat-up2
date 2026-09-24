# CP-07 (P1-020-01, P2-020-01; RISK-020-02 e RISK-021-02 confirmados no IP-01; SSOT §29.1/§30).
#
# Gera (ou rotaciona) o `engine_api_key` de um UpSales::AgentTenant e o entrega DIRETO no Vault do
# up2-agents (credencial `operational_engine` do tenant, criptografada lá), servidor a servidor, com
# a mesma autenticação TENANT_ADMIN (api_key do tenant) que a originação já usa. Ninguém copia o
# segredo à mão, ele não passa por ToolDefinitions/prompt/frontend e nunca é impresso nem logado:
# o retorno só traz status e identificadores.
#
# Ordem da rotação (RISK-020-02), CP-12: o digest da chave nova é gravado DENTRO de uma transação e
# a escrita no Vault acontece antes do commit. Se o Vault recusar, a transação volta e nada muda
# (a chave antiga segue valendo dos dois lados). Como aqui só existe o digest (P1-VAL-10), não há
# mais "chave antiga" legível para compensar: se o Vault aceitar e o commit falhar (raro), o
# consumidor fica com uma chave que este lado ainda não aceita -- basta rodar a rotação de novo.
#
# Mais de uma credencial `operational_engine` no tenant é ambiguidade (o up2-agents escolheria uma
# arbitrária -- RISK-021-02): recusa e pede resolução manual, em vez de escolher por conta própria.
class UpSales::Agents::ProvisionEngineApiKeyService
  class ProvisionError < StandardError; end

  VAULT_KIND = 'operational_engine'.freeze
  VAULT_NAME = 'Operational Engine (chat-up2)'.freeze

  def initialize(agent_tenant:)
    @agent_tenant = agent_tenant
  end

  def perform
    rotated = agent_tenant.engine_api_key_configured?
    current_entry_id = existing_entry_id
    entry_id = nil

    agent_tenant.transaction do
      new_key = agent_tenant.assign_new_engine_api_key
      agent_tenant.save!
      entry_id = write_vault(current_entry_id, new_key)
    end

    { rotated: rotated, vault_entry_id: entry_id, account_id: agent_tenant.account_id }
  end

  private

  attr_reader :agent_tenant

  def existing_entry_id
    response = request(:get, '/v1/vault')
    entries = Array(response['entries']).select { |entry| entry['kind'] == VAULT_KIND }
    if entries.size > 1
      raise ProvisionError, "#{entries.size} credenciais #{VAULT_KIND} no Vault do up2-agents -- deixe só uma antes de provisionar"
    end

    entries.first&.dig('id')
  end

  def write_vault(entry_id, key)
    body = { value: { accountId: agent_tenant.account_id.to_s, engineApiKey: key }, baseUrl: engine_base_url }
    response = if entry_id
                 request(:put, "/v1/vault/#{entry_id}", body)
               else
                 request(:post, '/v1/vault', body.merge(name: VAULT_NAME, kind: VAULT_KIND))
               end
    response['id'].presence || entry_id
  end

  def request(method, path, body = nil)
    response = HTTParty.send(method, "#{api_base_url}#{path}", headers: auth_headers, body: body&.to_json)
    # Nunca incluir o corpo enviado na mensagem de erro: ele carrega o segredo.
    raise ProvisionError, "up2-agents respondeu #{response.code} em #{method.upcase} #{path}" unless response.success?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  def auth_headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{agent_tenant.api_key}" }
  end

  # Origem pública deste chat-up2 -- o up2-agents monta /api/v1/accounts/:id/operational_engine/*.
  def engine_base_url
    ENV.fetch('FRONTEND_URL').chomp('/')
  end

  def api_base_url
    GlobalConfigService.load('UP2_AGENTS_API_URL', 'https://agents.up2aceleradora.com.br/api')
  end
end
