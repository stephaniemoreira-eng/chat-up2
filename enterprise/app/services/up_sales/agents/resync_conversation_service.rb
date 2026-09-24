# CP-16B (P2-VAL-20; decisão da Stéphanie em 24/09/2026 -- ver OperationalEngine::DevolucaoResync):
# pede ao up2-agents (POST /v1/chatwoot/resync) o turno SILENCIOSO de ressincronização da Lavínia
# depois de uma devolução humana. Mesmo desenho do RecoverConversationService (auth por tenant,
# Bearer api_key, api_base_url), com uma diferença de contrato: esta rota NUNCA posta -- o up2-agents
# só commita a saída estruturada no Engine (turn_id `devolucao:<devolucao_id>`, modo ressincronizacao).
#
# SyncError = o turno não chegou a commitar (up2-agents fora, Engine recusou, saída inválida) -- o
# DevolucaoResyncJob tenta de novo um número limitado de vezes. `outcome` "unchanged" (a Lavínia não
# viu ponto novo) é sucesso: "SE NECESSÁRIO".
class UpSales::Agents::ResyncConversationService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, conversation:, devolucao_id:)
    @agent_tenant = agent_tenant
    @conversation = conversation
    @devolucao_id = devolucao_id
  end

  def perform
    response = HTTParty.post("#{api_base_url}/v1/chatwoot/resync", headers: auth_headers, body: body.to_json, timeout: 120)
    raise SyncError, error_message(response) unless response.success?

    parsed = response.parsed_response
    raise SyncError, (parsed['reason'] || parsed['outcome'] || 'ressincronização recusada').to_s unless parsed.is_a?(Hash) && parsed['ok']

    parsed
  rescue *OperationalEngine::CalendarRetryAttempt::NETWORK_ERRORS => e
    raise SyncError, "up2-agents indisponível (#{e.class})"
  end

  private

  attr_reader :agent_tenant, :conversation, :devolucao_id

  def body
    {
      chatwootAccountId: agent_tenant.account_id,
      chatwootConversationId: conversation.display_id,
      chatwootInboxId: conversation.inbox_id,
      devolucaoId: devolucao_id
    }
  end

  def auth_headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{agent_tenant.api_key}" }
  end

  def error_message(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? (parsed['error'] || parsed['message'] || parsed['reason'] || parsed.to_s) : response.body.to_s
  end

  def api_base_url
    GlobalConfigService.load('UP2_AGENTS_API_URL', 'https://agents.up2aceleradora.com.br/api')
  end
end
