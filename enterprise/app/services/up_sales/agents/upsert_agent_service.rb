# Cria ou habilita/desabilita, no up2-agents, o agente correspondente a um UpSales::AgentSlot.
# A API do up2-agents não tem "tipo" de agente nem chave de plataforma entre tenants (verificado)
# -- por isso cada UpSales::AgentTenant guarda a própria chave (secv4_...) daquele tenant, e a
# diferenciação entre Prospecção/SDR, Follow-up e Secretária é só por nome (UpSales::AgentSlot::LABELS).
# O prompt de cada agente é escrito depois, direto no painel up2-agents -- essa tela só ativa/
# desativa o "slot". Ver docs/fork/ADR-0004-up-sales-reskin.md.
class UpSales::Agents::UpsertAgentService
  DEFAULT_SYSTEM_PROMPT = 'Configure o prompt deste agente no painel up2-agents.'.freeze

  class SyncError < StandardError; end

  def initialize(agent_tenant:, slot:)
    @agent_tenant = agent_tenant
    @slot = slot
  end

  def perform
    if slot.enabled?
      slot.up2_agents_agent_id.present? ? update_agent(enabled: true) : create_agent
    elsif slot.up2_agents_agent_id.present?
      update_agent(enabled: false)
    end
  end

  private

  attr_reader :agent_tenant, :slot

  def create_agent
    response = HTTParty.post(
      "#{api_base_url}/v1/agents",
      headers: auth_headers,
      body: { name: slot.label, systemPrompt: DEFAULT_SYSTEM_PROMPT, enabled: true }.to_json
    )
    raise SyncError, error_message(response) unless response.success?

    slot.update!(up2_agents_agent_id: response.parsed_response.dig('agent', 'id'))
  end

  def update_agent(enabled:)
    response = HTTParty.patch(
      "#{api_base_url}/v1/agents/#{slot.up2_agents_agent_id}",
      headers: auth_headers,
      body: { enabled: enabled }.to_json
    )
    raise SyncError, error_message(response) unless response.success?
  end

  def auth_headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{agent_tenant.api_key}" }
  end

  def error_message(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? (parsed['message'] || parsed.to_s) : response.body
  end

  def api_base_url
    GlobalConfigService.load('UP2_AGENTS_API_URL', 'https://agents.up2aceleradora.com.br')
  end
end
