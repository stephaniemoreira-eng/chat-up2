# acao_sugerida = handoff_comercial (SSOT §12.4/§17.1, S-4 parte 2). Diferente de
# TakeoverService (S-3/§18.2): aquele é um humano especifico clicando "Assumir" (precisa de
# user_id). Aqui é a própria Lavínia sinalizando "isto precisa do Comercial".
#
# CP-05 (P1-018-01, P1-018-02; SSOT §17.2, §17.3, §18.4, §7.4). Sucesso significa HANDOFF REAL
# concluído, com todas as dimensões do §17.2:
# - frente_operacional = comercial;
# - modo_atendimento = humano (a partir daqui a Lavínia não fala mais -- §12.4);
# - responsavel_atual_id = responsável Comercial -- resolvido SÓ em
#   OperationalEngine::CommercialResponsibleResolver (CP-16A, P2-VAL-16: o usuário Comercial
#   configurado na conta -- decisão da Stéphanie em 24/09/2026, "DANILO"). Sem humano responsável e
#   sem configuração, o responsável fica pendente e isso é explícito no retorno
#   (`responsavel_pendente: true`) e no evento, em vez de fingir que alguém foi atribuído;
# - etapa_comercial = oportunidade (cria se não havia; nunca rebaixa uma que já avançou);
# - recovery Prospect encerrada, aguardando_resposta = false;
# - snapshot/resumo da oportunidade (§17.3) no evento `handoff_comercial`.
#
# Idempotência pelo estado INTEGRAL do handoff, não por `modo_atendimento=humano`: um humano pode
# estar na conversa ainda em Prospecção (§18.4, "intervenção humana não cria handoff por si só") --
# nesse caso o handoff completa só o que falta. Replay com tudo já realizado é no-op: nenhum evento
# novo, nenhuma etapa rebaixada, motivo original preservado.
#
# Eventos (§7.4): `handoff_comercial` (motivo, de/para de cada dimensão, snapshot) + os canônicos de
# cada semântica que mudou: frente_operacional_alterada, modo_atendimento_alterado,
# responsavel_alterado, oportunidade_criada.
#
# CP-14 (P1-VAL-13): motivo `orcamento_personalizado` também grava `orcamento_status = personalizado`
# (OperationalEngine::BudgetStatus), com evento próprio `orcamento_personalizado` (de/para/motivo).
module OperationalEngine
  module Tools
    class HandoffToCommercialService
      SNAPSHOT_FIELDS = %i[
        nome empresa telefone origem_lead modo_entrada segmento modelo_atual dor_oportunidade impacto intencao_comercial
        regiao volume_mensal_kg retiradas_semana orcamento_status resumo_oportunidade
      ].freeze
      DIMENSION_EVENTS = {
        frente_operacional: 'frente_operacional_alterada',
        modo_atendimento: 'modo_atendimento_alterado',
        responsavel_atual_id: 'responsavel_alterado'
      }.freeze

      def initialize(account:, conversation_id:, motivo_handoff:)
        @account = account
        @conversation_id = conversation_id
        @motivo_handoff = motivo_handoff
      end

      def call
        return { ok: false, reason: 'motivo_handoff inválido' } unless OperationalEngine::Lead.motivo_handoffs.key?(@motivo_handoff)

        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)

        # Guardas dentro do lock (estado relido). A guarda de modo humano do LaviniaActionGuard NÃO
        # se aplica aqui de propósito: o handoff sobre um lead já em atendimento humano na
        # Prospecção é justamente o caso do §18.4 (P1-018-02).
        result = lead.with_lock do
          next { ok: false, reason: OperationalEngine::Tools::LaviniaActionGuard::NAO_CONTATAR } if lead.nao_contatar?

          register_orcamento_personalizado(lead)
          apply_handoff(lead)
        end
        OperationalEngine::ProjectionReconciler.flush(lead) if result[:ok]
        result
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end

      private

      # CP-14 (P1-VAL-13; §17.1, 28.13): handoff por orçamento personalizado reflete
      # `orcamento_status = personalizado` ANTES do snapshot do §17.3, sem valor nenhum. Direto na
      # transição (não em BudgetStatus.apply_turn!): o handoff vale também com humano na Prospecção
      # (§18.4). No agent mode o commit do turno já costuma ter gravado -- aqui vira no-op.
      def register_orcamento_personalizado(lead)
        return unless @motivo_handoff == 'orcamento_personalizado'

        OperationalEngine::BudgetStatus.personalizar!(lead, motivo: 'handoff_orcamento_personalizado')
      end

      def apply_handoff(lead)
        changes = target_state(lead).reject { |field, value| lead.public_send(field) == value }
        return success(lead) if changes.empty?

        before = changes.keys.index_with { |field| lead.public_send(field) }
        lead.update!(changes.merge(handoff_side_effects(changes)))
        write_events(lead, before)
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'handoff_comercial')
        success(lead)
      end

      def target_state(lead)
        responsavel = OperationalEngine::CommercialResponsibleResolver.call(lead: lead)
        {
          frente_operacional: 'comercial', modo_atendimento: 'humano',
          etapa_comercial: lead.etapa_comercial || 'oportunidade',
          recuperacao_status: 'inativa', proxima_recuperacao_em: nil, aguardando_resposta: false
        }.merge(responsavel ? { responsavel_atual_id: responsavel } : {})
      end

      # O motivo acompanha o handoff que de fato mudou algo; o timestamp do modo só quando o modo
      # muda (§18.2: início do modo atual).
      def handoff_side_effects(changes)
        { motivo_handoff: @motivo_handoff }.merge(changes.key?(:modo_atendimento) ? { modo_atendimento_entrou_em: Time.current } : {})
      end

      def success(lead)
        lead.responsavel_atual_id.present? ? { ok: true } : { ok: true, responsavel_pendente: true }
      end

      def write_events(lead, before)
        correlation_id = SecureRandom.uuid
        transicoes = before.to_h { |field, de| [field, { de: de, para: lead.public_send(field) }] }
        event(lead, 'handoff_comercial', correlation_id,
              motivo_handoff: @motivo_handoff, transicoes: transicoes,
              responsavel_pendente: lead.responsavel_atual_id.blank?, snapshot: snapshot(lead))
        write_dimension_events(lead, before, correlation_id)
      end

      def write_dimension_events(lead, before, correlation_id)
        DIMENSION_EVENTS.slice(*before.keys).each do |field, event_type|
          event(lead, event_type, correlation_id, de: before[field], para: lead.public_send(field), motivo: 'handoff_comercial')
        end
        return unless before.key?(:etapa_comercial) && before[:etapa_comercial].nil?

        OperationalEngine::ComercialOpportunity.registrar_evento!(
          lead, source: 'lavinia', motivo: 'handoff_comercial', correlation_id: correlation_id
        )
      end

      # §17.3: o que for conhecido, sem exigir ficha gigante -- campos vazios ficam fora.
      def snapshot(lead)
        SNAPSHOT_FIELDS.index_with { |field| lead.public_send(field) }.compact
                       .merge(motivo_handoff: @motivo_handoff, conversation_id: @conversation_id)
      end

      def event(lead, event_type, correlation_id, **metadata)
        OperationalEngine::LeadEvent.create!(lead: lead, event_type: event_type, source: 'lavinia',
                                              metadata: metadata.merge(correlation_id: correlation_id))
      end
    end
  end
end
