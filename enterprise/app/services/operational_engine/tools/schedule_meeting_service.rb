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
        return calendar_failure('agenda não conectada para esta conta') unless calendar_connected?(agent_tenant)

        conflict_reason = calendar_conflict_reason(agent_tenant)
        return calendar_failure(conflict_reason) if conflict_reason

        create_and_persist(lead, agent_tenant)
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      rescue UpSales::Agents::CreateCalendarEventService::SyncError,
             UpSales::Agents::ListCalendarEventsService::SyncError,
             *OperationalEngine::CalendarRetryAttempt::NETWORK_ERRORS => e
        # SSOT §16: falha do Calendar não pode confirmar reunião nem conversão -- nada é gravado.
        calendar_failure(e.message)
      end

      private

      # CP-16B (P2-VAL-19, decisão da Stéphanie em 24/09/2026): a falha é marcada como "do Calendar"
      # (`falha_calendar: true`) para o up2-agents saber que é a falha que a decisão manda tentar de
      # novo em silêncio e, na segunda, virar callback do Danilo -- diferente de uma recusa de
      # negócio (humano, não-contatar, encerrado, não qualificado), que não se tenta de novo.
      def calendar_failure(reason)
        { ok: false, reason: reason, falha_calendar: true }
      end

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

      # A lista de disponibilidade orienta a conversa, mas esta verificação protege a fronteira que
      # efetivamente cria o compromisso. O Google Calendar aceita sobreposições; sem revalidar aqui,
      # um modelo pode escolher um horário ocupado e ainda receber um event_id real. SSOT §3.6/§16.1:
      # evento real só confirma reunião quando o intervalo também estava disponível no instante da escrita.
      def calendar_conflict_reason(agent_tenant)
        events = UpSales::Agents::ListCalendarEventsService.new(
          agent_tenant: agent_tenant,
          time_min: @starts_at,
          time_max: @ends_at
        ).perform

        return 'horário indisponível na agenda' if events.any? { |event| overlaps_requested_interval?(event) }

        nil
      end

      # [start, end) mantém adjacências válidas: algo que termina exatamente quando a reunião começa
      # (ou começa exatamente quando ela termina) não é conflito. Evento sem intervalo legível falha
      # fechado: não há base segura para declarar o horário disponível.
      def overlaps_requested_interval?(event)
        event_start = calendar_event_time(event, 'start')
        event_end = calendar_event_time(event, 'end')
        return true if event_start.nil? || event_end.nil?

        event_start < requested_end && event_end > requested_start
      end

      def requested_start
        @requested_start ||= Time.iso8601(@starts_at)
      end

      def requested_end
        @requested_end ||= Time.iso8601(@ends_at)
      end

      def calendar_event_time(event, boundary)
        value = event[boundary] || event[boundary.to_sym] || event["#{boundary}_at"] || event["#{boundary}s_at"]
        value = value['dateTime'] || value['date_time'] || value['date'] if value.is_a?(Hash)
        Time.iso8601(value) if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      def create_and_persist(lead, agent_tenant)
        event = UpSales::Agents::CreateCalendarEventService.new(
          agent_tenant: agent_tenant,
          summary: @summary,
          starts_at: @starts_at,
          ends_at: @ends_at,
          description: @description
        ).perform

        event_id = event.is_a?(Hash) ? event['id'] : nil
        return calendar_failure('up2-agents não retornou um event_id válido') if event_id.blank?

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
          # CP-09 (P1-VAL-05; SSOT §16.1 "Prospect continua Qualificado" até o sucesso real, §13.2
          # rota curta, §13.3): uma reunião realmente criada no Calendar é evidência de oportunidade
          # real -- se o lead ainda não estava Qualificado, a qualificação é persistida no MESMO lock,
          # antes do Agendado (nenhum lead chega a Agendado sem ter passado por Qualificado).
          OperationalEngine::QualificationService.qualificar!(lead, source: 'lavinia')
          confirm_meeting!(lead, event_id, now)
          # CP-09 (P1-VAL-05; §16.1 "criar/manter oportunidade Comercial"): mesmo caminho do callback
          # e do handoff -- cria só se não havia, nunca rebaixa. Frente operacional e modo de
          # atendimento não mudam: reunião confirmada não é handoff (§17.2).
          OperationalEngine::ComercialOpportunity.garantir!(lead, source: 'lavinia', motivo: 'reuniao_agendada')
          OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'reuniao_agendada')
        end

        # Fora do with_lock de propósito (mesma razão do TakeoverService): a sincronização toca o
        # Postgres nativo, um banco diferente do Supabase -- não vale segurar o lock pela viagem
        # de rede extra. CP-05: projeção durável via OperationalEngine::ProjectionReconciler.
        OperationalEngine::ProjectionReconciler.flush(lead)
      end

      def confirm_meeting!(lead, event_id, now)
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
      end
    end
  end
end
