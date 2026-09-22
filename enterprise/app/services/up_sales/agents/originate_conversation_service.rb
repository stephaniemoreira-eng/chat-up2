# Chama o endpoint novo do up2-agents (POST /v1/chatwoot/originate) pra originar o primeiro
# contato -- a Lavínia gera e ENVIA a mensagem de abertura ela mesma (decisão registrada: reusa o
# mesmo caminho já testado de toda resposta reativa, em vez de inventar um contrato novo de
# "devolver texto pro Rails enviar"). Espelha UpdateCalendarEventService: mesma auth por tenant
# (Bearer api_key), mesmo api_base_url.
class UpSales::Agents::OriginateConversationService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, conversation:, contact_inbox:)
    @agent_tenant = agent_tenant
    @conversation = conversation
    @contact_inbox = contact_inbox
  end

  def perform
    response = HTTParty.post(
      "#{api_base_url}/v1/chatwoot/originate",
      headers: auth_headers,
      body: body.to_json
    )
    raise SyncError, error_message(response) unless response.success?

    parsed = response.parsed_response
    raise SyncError, parsed['reason'] || 'origination recusada' unless parsed['ok']

    parsed
  end

  private

  attr_reader :agent_tenant, :conversation, :contact_inbox

  def body
    contact = contact_inbox.contact
    {
      agentId: agent_tenant.prospecting_agent_id.to_s,
      chatwootAccountId: agent_tenant.account_id,
      chatwootConversationId: conversation.display_id,
      chatwootInboxId: contact_inbox.inbox_id,
      chatwootContactId: contact.id,
      contactInboxId: contact_inbox.id,
      contactName: contact.name,
      contactPhone: contact.phone_number
    }.compact
  end

  def auth_headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{agent_tenant.api_key}" }
  end

  def error_message(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? (parsed['error'] || parsed['message'] || parsed.to_s) : response.body
  end

  def api_base_url
    GlobalConfigService.load('UP2_AGENTS_API_URL', 'https://agents.up2aceleradora.com.br/api')
  end
end
