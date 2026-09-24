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

        # CP-10 (P1-VAL-03; SSOT §12.4/§23.2): esta rota agora é chamada pela ferramenta "Criar
        # evento" da Lavínia no modo agent -- as mesmas guardas do iniciar_agendamento valem aqui,
        # e ANTES do Calendar: um lead em atendimento humano/não-contatar/encerrado não pode ganhar
        # um evento real que depois ninguém confirmaria.
        reason = blocked_reason(lead)
        return { ok: false, reason: reason } if reason

        # `ja_existia`: a reunião confirmada é a de antes, nada novo foi criado. O chamador precisa
        # saber disso para não anunciar um horário diferente como "agendado" (reagendar é o
        # UpdateMeetingService).
        already_confirmed = lead.agendamento_status_confirmado? && lead.calendar_event_id.present?
        return { ok: true, event_id: lead.calendar_event_id, ja_existia: true } if already_confirmed

        agent_tenant = @account.up_sales_agent_tenant
        return { ok: false, reason: 'agenda não conectada para esta conta' } unless calendar_connected?(agent_tenant)

        create_and_persist(lead, agent_tenant)
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      rescue UpSales::Agents::CreateCalendarEventService::SyncError => e
        # SSOT §16: falha do Calendar não pode confirmar reunião nem conversão -- nada é gravado.
        { ok: false, reason: e.message }
      end

      private

      # Lido fora do lock de propósito: o Calendar é chamado depois, e segurar o lock do lead pela
      # viagem de rede ao up2-agents/Google não compensa. Se um humano assumir entre esta leitura e a
      # gravação, o evento JÁ existe no Calendar (fonte real, §3.6) -- confirmá-lo continua verdadeiro;
      # o que a guarda impede é a Lavínia CRIAR um compromisso para um lead que não é mais dela.
      def blocked_reason(lead)
        reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead, nao_contatar: true)
        return reason if reason
        return 'lead encerrado' if lead.lead_status_encerrado?

        'lead não qualificado' if lead.qualificacao_status_nao_qualificado?
      end

      def calendar_connected?(agent_tenant)
        agent_tenant.present? && agent_tenant.calendar_integration_instance_id.present?
      end

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
        # Um só Time.current, reaproveitado nos dois campos: conversao_em = agendado_em quando é
        # a reunião que converte (SSOT §16.3, "conversao_em = min(agendado_em, ...)"). Duas
        # chamadas separadas produziriam dois instantes com microssegundos diferentes -- quebraria
        # essa igualdade por um detalhe de timing, não por regra de negócio.
        now = Time.current
        lead.with_lock do
          lead.update!(
            calendar_event_id: event_id,
            agendamento_status: 'confirmado',
            agendado_em: now,
            etapa_prospect: 'agendado',
            **(lead.conversao_em.nil? ? { conversao_em: now, tipo_conversao: 'agendamento' } : {})
          )
          OperationalEngine::LeadEvent.create!(
            lead: lead,
            event_type: 'reuniao_agendada',
            source: 'lavinia',
            metadata: { calendar_event_id: event_id, correlation_id: SecureRandom.uuid }
          )
          OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'reuniao_agendada')
        end

        # Fora do with_lock de propósito (mesma razão do TakeoverService): a sincronização toca o
        # Postgres nativo, um banco diferente do Supabase -- não vale segurar o lock pela viagem
        # de rede extra. CP-05: projeção durável via OperationalEngine::ProjectionReconciler.
        OperationalEngine::ProjectionReconciler.flush(lead)
      end
    end
  end
end
