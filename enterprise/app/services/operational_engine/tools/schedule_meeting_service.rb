# S-5 / Contrato B / SSOT §16 + §5.6: só grava agendamento_status=confirmado depois de um
# calendar_event_id REAL vindo do up2-agents -- nunca antes ("confirmar agendamento sem
# calendar_event_id real" é proibição explícita do Marco 1). Reaproveita
# UpSales::Agents::CreateCalendarEventService (mesmo HTTP/auth que o botão "Agendar" humano já
# usa em ContactPanel.vue), pra não duplicar a chamada ao up2-agents nem divergir dela.
module OperationalEngine
  module Tools
    class ScheduleMeetingService
      def initialize(account:, conversation_id:, summary:, starts_at:, ends_at:, description: nil)
        @account = account
        @conversation_id = conversation_id
        @summary = summary
        @starts_at = starts_at
        @ends_at = ends_at
        @description = description
      end

      def call
        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        already_confirmed = lead.agendamento_status_confirmado? && lead.calendar_event_id.present?
        return { ok: true, event_id: lead.calendar_event_id } if already_confirmed

        agent_tenant = @account.up_sales_agent_tenant
        if agent_tenant.blank? || agent_tenant.calendar_integration_instance_id.blank?
          return { ok: false, reason: 'agenda não conectada para esta conta' }
        end

        create_and_persist(lead, agent_tenant)
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      rescue UpSales::Agents::CreateCalendarEventService::SyncError => e
        # SSOT §16: falha do Calendar não pode confirmar reunião nem conversão -- nada é gravado.
        { ok: false, reason: e.message }
      end

      private

      def create_and_persist(lead, agent_tenant)
        event = UpSales::Agents::CreateCalendarEventService.new(
          agent_tenant: agent_tenant,
          summary: @summary,
          starts_at: @starts_at,
          ends_at: @ends_at,
          description: @description
        ).perform

        event_id = event['id']
        return { ok: false, reason: 'up2-agents não retornou um event_id válido' } if event_id.blank?

        persist_confirmation(lead, event_id)
        { ok: true, event_id: event_id }
      end

      # Idempotente pra chamadas repetidas em sequência (o early-return em `call`), não pra duas
      # chamadas SIMULTÂNEAS pro mesmo lead -- isso criaria dois eventos no Google Calendar, um
      # desperdiçado. Aceito por ora: a Lavínia processa uma conversa por vez, então essa corrida
      # exige um cenário que a arquitetura atual não produz (mesmo desvio consciente do §5.9).
      def persist_confirmation(lead, event_id)
        lead.with_lock do
          lead.update!(
            calendar_event_id: event_id,
            agendamento_status: 'confirmado',
            agendado_em: Time.current,
            etapa_prospect: 'agendado',
            **(lead.conversao_em.nil? ? { conversao_em: Time.current, tipo_conversao: 'agendamento' } : {})
          )
          OperationalEngine::LeadEvent.create!(
            lead: lead,
            event_type: 'reuniao_agendada',
            source: 'lavinia',
            metadata: { calendar_event_id: event_id, correlation_id: SecureRandom.uuid }
          )
        end

        # Fora do with_lock de propósito (mesma razão do TakeoverService): a sincronização toca o
        # Postgres nativo, um banco diferente do Supabase -- não vale segurar o lock pela viagem
        # de rede extra.
        OperationalEngine::SalesProjectionSync.call(lead)
      end
    end
  end
end
