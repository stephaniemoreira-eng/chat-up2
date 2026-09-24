# S-5 (parte 2, agora que o S-9 existe no up2-agents) / Contrato B: cancela uma reunião JÁ
# confirmada. Mesma checagem de sanidade do UpdateMeetingService (event_id da URL == calendar_event_id
# atual do lead).
#
# CP-04 (P1-023-01, SSOT §28.29 "não voltar automaticamente Agendado→Qualificado"): grava só
# agendamento_status=cancelado + evento reuniao_cancelada. A etapa Prospect NÃO regride -- a reunião
# real existiu e o Agendado continua sendo o fato histórico do funil. calendar_event_id, agendado_em
# e conversao_em/tipo_conversao também ficam intactos (§6.3: fatos históricos; conversão é
# write-once). Uma nova reunião confirmada depois sobrescreve normalmente via ScheduleMeetingService.
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
          lead.update!(agendamento_status: 'cancelado')
          OperationalEngine::LeadEvent.create!(
            lead: lead,
            event_type: 'reuniao_cancelada',
            source: 'lavinia',
            metadata: { calendar_event_id: @event_id, correlation_id: SecureRandom.uuid }
          )
          OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'reuniao_cancelada')
        end

        # Fora do with_lock (mesma razão do ScheduleMeetingService/TakeoverService). CP-05: projeção
        # durável via OperationalEngine::ProjectionReconciler.
        OperationalEngine::ProjectionReconciler.flush(lead)
      end
    end
  end
end
