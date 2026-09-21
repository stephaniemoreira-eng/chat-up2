# S-5 (parte 2, agora que o S-9 existe no up2-agents) / Contrato B: cancela uma reunião JÁ
# confirmada. Mesma checagem de sanidade do UpdateMeetingService (event_id da URL == calendar_event_id
# atual do lead).
#
# Volta agendamento_status pra cancelado e etapa_prospect pra qualificado (a etapa logo antes de
# agendado -- sem reunião confirmada, o lead volta a ser "só" qualificado). NÃO toca
# conversao_em/tipo_conversao: são write-once no banco (a trigger recusaria) e, mais importante,
# cancelar uma reunião não desfaz o fato histórico de que uma conversão aconteceu naquele momento --
# é uma métrica de "tempo até converter", não um estado que reflete a reunião em si. calendar_event_id
# também fica como está (referência histórica); uma chamada futura de schedule_meeting sobrescreve
# normalmente quando uma nova reunião for confirmada.
module OperationalEngine
  module Tools
    class CancelMeetingService
      def initialize(account:, conversation_id:, event_id:)
        @account = account
        @conversation_id = conversation_id
        @event_id = event_id
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        return not_the_confirmed_meeting unless matches_confirmed_meeting?(lead)

        agent_tenant = @account.up_sales_agent_tenant
        if agent_tenant.blank? || agent_tenant.calendar_integration_instance_id.blank?
          return { ok: false, reason: 'agenda não conectada para esta conta' }
        end

        UpSales::Agents::CancelCalendarEventService.new(agent_tenant: agent_tenant, event_id: @event_id).perform

        persist_cancellation(lead)
        { ok: true }
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      rescue UpSales::Agents::CancelCalendarEventService::SyncError => e
        { ok: false, reason: e.message }
      end

      private

      def matches_confirmed_meeting?(lead)
        lead.agendamento_status_confirmado? && lead.calendar_event_id == @event_id
      end

      def not_the_confirmed_meeting
        { ok: false, reason: 'este lead não tem uma reunião confirmada com esse event_id' }
      end

      def persist_cancellation(lead)
        lead.with_lock do
          lead.update!(agendamento_status: 'cancelado', etapa_prospect: 'qualificado')
          OperationalEngine::LeadEvent.create!(
            lead: lead,
            event_type: 'reuniao_cancelada',
            source: 'lavinia',
            metadata: { calendar_event_id: @event_id, correlation_id: SecureRandom.uuid }
          )
        end

        # Fora do with_lock (mesma razão do ScheduleMeetingService/TakeoverService).
        OperationalEngine::SalesProjectionSync.call(lead)
      end
    end
  end
end
