# S-5 (parte 2, agora que o S-9 existe no up2-agents) / Contrato B: reagenda uma reunião JÁ
# confirmada. Exige que o event_id da URL bata com o calendar_event_id atual do lead -- não é uma
# checagem de dono por carimbo (como o toolpack do agente faz), é só sanidade: recusa reagendar algo
# que não é a reunião confirmada de verdade deste lead, em vez de aceitar qualquer id.
#
# Não muda agendamento_status/etapa_prospect/conversao_em: a reunião continua confirmada, só a
# data/hora ou os detalhes mudaram -- nenhum desses campos representa "quando a reunião acontece",
# só "que ela foi confirmada" (§16). O horário real vive só no Google Calendar, via calendar_event_id.
module OperationalEngine
  module Tools
    class UpdateMeetingService
      def initialize(account:, conversation_id:, event_id:, summary: nil, starts_at: nil, ends_at: nil, description: nil)
        @account = account
        @conversation_id = conversation_id
        @event_id = event_id
        @summary = summary
        @starts_at = starts_at
        @ends_at = ends_at
        @description = description
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        return not_the_confirmed_meeting unless matches_confirmed_meeting?(lead)

        agent_tenant = @account.up_sales_agent_tenant
        if agent_tenant.blank? || agent_tenant.calendar_integration_instance_id.blank?
          return { ok: false, reason: 'agenda não conectada para esta conta' }
        end

        event = UpSales::Agents::UpdateCalendarEventService.new(
          agent_tenant: agent_tenant,
          event_id: @event_id,
          summary: @summary,
          starts_at: @starts_at,
          ends_at: @ends_at,
          description: @description
        ).perform

        record_event(lead)
        { ok: true, event_id: event['id'] || @event_id }
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      rescue UpSales::Agents::UpdateCalendarEventService::SyncError => e
        { ok: false, reason: e.message }
      end

      private

      def matches_confirmed_meeting?(lead)
        lead.agendamento_status_confirmado? && lead.calendar_event_id == @event_id
      end

      def not_the_confirmed_meeting
        { ok: false, reason: 'este lead não tem uma reunião confirmada com esse event_id' }
      end

      def record_event(lead)
        OperationalEngine::LeadEvent.create!(
          lead: lead,
          event_type: 'reuniao_reagendada',
          source: 'lavinia',
          metadata: { calendar_event_id: @event_id, correlation_id: SecureRandom.uuid }
        )
      end
    end
  end
end
