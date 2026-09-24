# CP-13 (P1-VAL-12; SSOT §15.2, §15.6, §12.3): pede ao up2-agents (POST /v1/chatwoot/recover) que a
# Lavínia gere e envie UMA mensagem de recovery na conversa do ciclo, com Snapshot
# contexto_execucao=recuperacao (ultimo_ponto + fatos + histórico recente). Mesmo desenho do
# OriginateConversationService: mesma auth por tenant (Bearer api_key), mesmo api_base_url.
#
# O agente NÃO é enviado: o up2-agents resolve o agente da inbox da conversa (espelho), porque o
# recovery pode acontecer tanto na inbox de Prospecção quanto numa conversa que o lead abriu na
# inbox Comercial (§5.3.1). A autorização do post é a RecoveryActivation (recoveryActivationId), que
# o up2-agents carimba no post (up2_automation.kind=RECUPERACAO) e o OutboundSendGate valida.
class UpSales::Agents::RecoverConversationService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, conversation:, activation:)
    @agent_tenant = agent_tenant
    @conversation = conversation
    @activation = activation
  end

  def perform
    response = HTTParty.post("#{api_base_url}/v1/chatwoot/recover", headers: auth_headers, body: body.to_json, timeout: 120)
    raise SyncError, error_message(response) unless response.success?

    parsed = response.parsed_response
    raise SyncError, (parsed['reason'] || parsed['outcome'] || 'recovery recusada').to_s unless parsed.is_a?(Hash) && parsed['ok']

    parsed
  end

  private

  attr_reader :agent_tenant, :conversation, :activation

  def body
    {
      chatwootAccountId: agent_tenant.account_id,
      chatwootConversationId: conversation.display_id,
      chatwootInboxId: conversation.inbox_id,
      recoveryActivationId: activation.activation_id,
      tentativa: activation.tentativa,
      authorizedAt: activation.authorized_at&.iso8601(6)
    }.compact
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
