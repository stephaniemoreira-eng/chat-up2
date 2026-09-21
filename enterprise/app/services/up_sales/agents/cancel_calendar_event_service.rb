# Cancela (exclui) um evento no Google Calendar do tenant, via a rota nova do up2-agents (S-9,
# DELETE /v1/integrations/instances/:id/calendar/events/:eventId). Espelha CreateCalendarEventService
# (mesma auth por tenant, mesmo instance id). A idempotência (410 do Google == sucesso) já é
# absorvida pelo próprio up2-agents -- essa rota sempre responde 2xx tanto num cancelamento novo
# quanto num já cancelado antes, então aqui basta checar response.success? como qualquer outra
# chamada; um 404 de verdade (evento nunca existiu) ainda chega como erro.
class UpSales::Agents::CancelCalendarEventService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, event_id:)
    @agent_tenant = agent_tenant
    @event_id = event_id
  end

  def perform
    raise SyncError, 'Nenhum calendário configurado para esta conta.' if agent_tenant.calendar_integration_instance_id.blank?

    response = HTTParty.delete(
      "#{api_base_url}/v1/integrations/instances/#{agent_tenant.calendar_integration_instance_id}/calendar/events/#{event_id}",
      headers: auth_headers
    )
    raise SyncError, error_message(response) unless response.success?

    true
  end

  private

  attr_reader :agent_tenant, :event_id

  def auth_headers
    { 'Authorization' => "Bearer #{agent_tenant.api_key}" }
  end

  def error_message(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? (parsed['error'] || parsed['message'] || parsed.to_s) : response.body
  end

  def api_base_url
    GlobalConfigService.load('UP2_AGENTS_API_URL', 'https://agents.up2aceleradora.com.br/api')
  end
end
