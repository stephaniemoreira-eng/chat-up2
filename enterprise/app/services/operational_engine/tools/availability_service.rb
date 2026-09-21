# S-5 / Contrato B: leitura pura -- devolve os eventos existentes no calendário conectado da
# conta pra Lavínia raciocinar sobre horários livres. Não calcula "slots livres" (horário
# comercial, duração de reunião etc. não têm regra definida em lugar nenhum do SSOT ainda) -- essa
# composição fica pro prompt, do mesmo jeito que a tool nativa consultar_agenda do LangGraph já
# faz. Reaproveita UpSales::Agents::ListCalendarEventsService (mesmo HTTP/auth da tela "Agenda").
module OperationalEngine
  module Tools
    class AvailabilityService
      def initialize(account:, time_min: nil, time_max: nil)
        @account = account
        @time_min = time_min
        @time_max = time_max
      end

      def call
        agent_tenant = @account.up_sales_agent_tenant
        if agent_tenant.blank? || agent_tenant.calendar_integration_instance_id.blank?
          return { ok: false, reason: 'agenda não conectada para esta conta' }
        end

        events = UpSales::Agents::ListCalendarEventsService.new(
          agent_tenant: agent_tenant,
          time_min: @time_min,
          time_max: @time_max
        ).perform

        { ok: true, events: events }
      rescue UpSales::Agents::ListCalendarEventsService::SyncError => e
        { ok: false, reason: e.message }
      end
    end
  end
end
