# S-5 / Contrato B: leitura pura da disponibilidade verificável. Eventos ocupados nunca provam
# disponibilidade no complemento; por isso a fonte é o endpoint de slots do up2-agents, que aplica
# Calendar real, bloqueios, horários de atendimento, duração e granularidade configuradas antes de
# devolver uma faixa que a Lavínia possa oferecer. Este serviço jamais infere um horário a partir de
# uma lista de eventos.
module OperationalEngine
  module Tools
    class AvailabilityService
      class SyncError < StandardError; end

      def initialize(account:, time_min: nil, time_max: nil)
        @agent_tenant = account.up_sales_agent_tenant
        @time_min = time_min
        @time_max = time_max
      end

      def call
        if agent_tenant.blank? || agent_tenant.calendar_integration_instance_id.blank?
          return { ok: false, reason: 'agenda não conectada para esta conta' }
        end

        response = HTTParty.get(
          "#{api_base_url}/v1/integrations/instances/#{agent_tenant.calendar_integration_instance_id}/calendar/availability",
          headers: auth_headers,
          query: { timeMin: @time_min, timeMax: @time_max }.compact
        )
        raise SyncError, error_message(response) unless response.success?

        payload = response.parsed_response
        return { ok: false, reason: 'agenda devolveu disponibilidade inválida' } unless payload.is_a?(Hash)

        availability = payload['availability']
        unless availability.is_a?(Hash) && availability['slots'].is_a?(Array)
          return { ok: false, reason: 'agenda devolveu disponibilidade inválida' }
        end

        { ok: true, slots: availability['slots'] }
      rescue SyncError => e
        { ok: false, reason: e.message }
      end

      private

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

      attr_reader :agent_tenant
    end
  end
end
