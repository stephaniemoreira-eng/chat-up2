# Cria um evento no Google Calendar do tenant, via a rota nova do up2-agents
# (POST /v1/integrations/instances/:id/calendar/events -- não existe chamada de agente aqui, é
# direto por REST, pra um operador humano agendando pela tela de Conversas). O evento criado não
# carrega o carimbo de contato que o próprio agente de IA usa (isso é um detalhe da conversa do
# agente, não desta chamada direta) -- ver o comentário em UpsertAgentService sobre não existir
# chave de API entre tenants. Ver docs/fork/ADR-0004-up-sales-reskin.md.
class UpSales::Agents::CreateCalendarEventService
  class SyncError < StandardError; end

  def initialize(agent_tenant:, summary:, starts_at:, ends_at:, description: nil)
    @agent_tenant = agent_tenant
    @summary = summary
    @starts_at = starts_at
    @ends_at = ends_at
    @description = description
  end

  def perform
    raise SyncError, 'Nenhum calendário configurado para esta conta.' if agent_tenant.calendar_integration_instance_id.blank?

    response = HTTParty.post(
      "#{api_base_url}/v1/integrations/instances/#{agent_tenant.calendar_integration_instance_id}/calendar/events",
      headers: auth_headers,
      body: {
        summary: summary,
        start: starts_at,
        end: ends_at,
        description: description
      }.compact.to_json
    )
    raise SyncError, error_message(response) unless response.success?

    response.parsed_response['event']
  end

  private

  attr_reader :agent_tenant, :summary, :starts_at, :ends_at, :description

  def auth_headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{agent_tenant.api_key}" }
  end

  def error_message(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? (parsed['error'] || parsed['message'] || parsed.to_s) : response.body
  end

  def api_base_url
    GlobalConfigService.load('UP2_AGENTS_API_URL', 'https://agents.up2aceleradora.com.br')
  end
end
