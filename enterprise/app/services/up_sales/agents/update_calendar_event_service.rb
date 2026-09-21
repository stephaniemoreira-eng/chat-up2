# Atualiza um evento existente no Google Calendar do tenant, via a rota nova do up2-agents (S-9,
# PATCH /v1/integrations/instances/:id/calendar/events/:eventId). Espelha CreateCalendarEventService
# (mesma auth por tenant, mesmo instance id) -- só os campos informados entram no body, igual ao
# PATCH parcial que a própria rota do up2-agents espera.
class UpSales::Agents::UpdateCalendarEventService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, event_id:, summary: nil, starts_at: nil, ends_at: nil, description: nil)
    @agent_tenant = agent_tenant
    @event_id = event_id
    @summary = summary
    @starts_at = starts_at
    @ends_at = ends_at
    @description = description
  end

  def perform
    raise SyncError, 'Nenhum calendário configurado para esta conta.' if agent_tenant.calendar_integration_instance_id.blank?

    body = { summary: summary, start: starts_at, end: ends_at, description: description }.compact
    raise SyncError, 'Nenhum campo informado para atualizar.' if body.empty?

    response = HTTParty.patch(
      "#{api_base_url}/v1/integrations/instances/#{agent_tenant.calendar_integration_instance_id}/calendar/events/#{event_id}",
      headers: auth_headers,
      body: body.to_json
    )
    raise SyncError, error_message(response) unless response.success?

    response.parsed_response['event']
  end

  private

  attr_reader :agent_tenant, :event_id, :summary, :starts_at, :ends_at, :description

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
