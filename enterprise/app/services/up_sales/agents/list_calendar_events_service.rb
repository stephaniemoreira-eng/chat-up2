# Lista os proximos eventos do Google Calendar do tenant, via a rota nova do up2-agents
# (GET /v1/integrations/instances/:id/calendar/events) -- espelha CreateCalendarEventService
# (mesma auth por tenant, mesmo instance id), so que somente leitura. Usado pela tela "Agenda
# integrada" do Up Sales. Ver docs/fork/ADR-0004-up-sales-reskin.md.
class UpSales::Agents::ListCalendarEventsService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, time_min: nil, time_max: nil, max_results: nil)
    @agent_tenant = agent_tenant
    @time_min = time_min
    @time_max = time_max
    @max_results = max_results
  end

  def perform
    raise SyncError, 'Nenhum calendário configurado para esta conta.' if agent_tenant.calendar_integration_instance_id.blank?

    response = HTTParty.get(
      "#{api_base_url}/v1/integrations/instances/#{agent_tenant.calendar_integration_instance_id}/calendar/events",
      headers: auth_headers,
      query: { timeMin: time_min, timeMax: time_max, maxResults: max_results }.compact
    )
    raise SyncError, error_message(response) unless response.success?

    response.parsed_response['events'] || []
  end

  private

  attr_reader :agent_tenant, :time_min, :time_max, :max_results

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
