# S-5 / Contrato B: leitura pura da agenda conectada. Eventos ocupados são dados diagnósticos; eles
# não autorizam o modelo a deduzir que qualquer outro horário é livre. O Engine calcula intervalos
# livres da janela pedida e os devolve como evidência verificável para a Lavínia (SSOT §§3.6 e 16.1).
module OperationalEngine
  module Tools
    class AvailabilityService
      MAX_WINDOW_SECONDS = 24.hours.to_i
      TIME_ZONE = 'America/Sao_Paulo'

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

        window = requested_window
        return window if window[:ok] == false

        events = UpSales::Agents::ListCalendarEventsService.new(
          agent_tenant: agent_tenant,
          time_min: @time_min,
          time_max: @time_max,
          max_results: 50
        ).perform

        intervals = busy_intervals(events, window[:start], window[:end])
        return intervals if intervals[:ok] == false

        { ok: true, events: events, slots: free_intervals(intervals[:intervals], window[:start], window[:end]) }
      rescue UpSales::Agents::ListCalendarEventsService::SyncError, ArgumentError => e
        { ok: false, reason: e.message }
      end

      private

      def requested_window
        starts_at = Time.iso8601(@time_min)
        ends_at = Time.iso8601(@time_max)
        return { ok: false, reason: 'janela de agenda inválida' } if ends_at <= starts_at || (ends_at - starts_at) > MAX_WINDOW_SECONDS

        { ok: true, start: starts_at, end: ends_at }
      rescue ArgumentError, TypeError
        { ok: false, reason: 'janela de agenda inválida' }
      end

      # An event with no usable interval cannot safely be ignored: a partial answer would make the
      # Engine offer a time that may in fact be blocked in Google Calendar.
      def busy_intervals(events, window_start, window_end)
        intervals = events.map do |event|
          starts_at = event_time(event, 'start')
          ends_at = event_time(event, 'end')
          return { ok: false, reason: 'agenda retornou evento sem intervalo verificável' } if starts_at.nil? || ends_at.nil? || ends_at <= starts_at

          [ [ starts_at, window_start ].max, [ ends_at, window_end ].min ]
        end.select { |starts_at, ends_at| starts_at < ends_at }

        { ok: true, intervals: intervals.sort_by(&:first) }
      end

      # Return maximal free intervals instead of inventing a meeting duration. The subsequent
      # ScheduleMeetingService still rechecks the exact requested interval immediately before the
      # Calendar write, so the Calendar remains the source of truth at both read and write time.
      def free_intervals(intervals, window_start, window_end)
        cursor = [ window_start, Time.current ].max
        slots = []

        intervals.each do |starts_at, ends_at|
          slots << render_slot(cursor, starts_at) if starts_at > cursor
          cursor = [ cursor, ends_at ].max
          break if cursor >= window_end
        end
        slots << render_slot(cursor, window_end) if cursor < window_end
        slots
      end

      def render_slot(starts_at, ends_at)
        {
          start: starts_at.iso8601,
          end: ends_at.iso8601,
          label: "#{starts_at.in_time_zone(TIME_ZONE).strftime('%a %d/%m %H:%M')}–#{ends_at.in_time_zone(TIME_ZONE).strftime('%a %d/%m %H:%M')}"
        }
      end

      def event_time(event, boundary)
        value = event[boundary] || event[boundary.to_sym] || event["#{boundary}_at"] || event["#{boundary}s_at"]
        value = value['dateTime'] || value['date_time'] || value['date'] if value.is_a?(Hash)
        Time.iso8601(value) if value.present?
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
