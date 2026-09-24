# CP-03 (P1-021-02; SSOT §3.5 "Lavínia interpreta; Engine valida, persiste e move", §12.4, §13.3,
# §15.2). O "commit do turno": aplica a parte SEMÂNTICA da saída estruturada da Lavínia -- o que ela
# aprendeu e decidiu -- como verdade operacional, antes de qualquer acao_sugerida ser despachada.
#
# Regras de validação (§12.4 + Prompt V1.0 §"dados_extraidos"):
# - dados_extraidos: só os fatos da whitelist abaixo (colunas do lead que o próprio Snapshot expõe
#   em identidade/conhecimento); chave desconhecida ou valor fora do tipo é ignorado e reportado;
#   null/vazio NUNCA apaga o valor já persistido;
# - decisao_qualificacao: semântica, não movimento de Kanban -- `qualificado` passa pelo
#   QualificationService (§13.3), `nao_qualificado` encerra (§13.3) exceto se houver reunião
#   confirmada, `em_qualificacao`/`nao_concluido` só atualizam o status sem regredir quem já é
#   qualificado; `sem_alteracao` não faz nada;
# - aguardando_resposta / ultimo_ponto / resumo_oportunidade: gravados quando presentes (§15.2: o
#   timer de recovery nasce no Engine a partir deste flag -- o ciclo de recovery em si é Fase 7);
# - modo_atendimento=humano: nada é aplicado (§12.4 "nenhuma ação da Lavínia").
#
# Tudo dentro do lock do lead, num só commit. Chamado via TurnIdempotency pelo controller, com a
# mesma identidade de turno das ações.
module OperationalEngine
  class ApplyStructuredOutputService
    TEXT_FACTS = %w[nome empresa email segmento regiao modelo_atual dor_oportunidade impacto cep].freeze
    ENUM_FACTS = { 'intencao_comercial' => OperationalEngine::Lead.intencao_comercials.keys }.freeze
    NUMERIC_FACTS = %w[volume_mensal_kg].freeze
    INTEGER_FACTS = %w[retiradas_semana].freeze
    DECISOES = %w[sem_alteracao em_qualificacao qualificado nao_qualificado nao_concluido].freeze
    TEXT_MAX = 2000

    def initialize(account:, conversation_id:, saida:)
      @account = account
      @conversation_id = conversation_id
      @saida = (saida || {}).to_h.stringify_keys
    end

    def call
      lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
      decisao = @saida['decisao_qualificacao'].presence || 'sem_alteracao'
      return { ok: false, reason: 'decisao_qualificacao inválida' } unless DECISOES.include?(decisao)

      result = lead.with_lock { apply(lead, decisao) }
      return result unless result[:ok]

      OperationalEngine::SalesProjectionSync.call(lead)
      OperationalEngine::ComercialProjectionSync.call(lead)
      result
    rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
      { ok: false, reason: e.message }
    end

    private

    def apply(lead, decisao)
      reason = OperationalEngine::Tools::LaviniaActionGuard.blocked_reason(lead)
      return { ok: false, reason: reason } if reason

      facts, ignored = extracted_facts
      changes = facts.merge(continuity_changes).reject { |field, value| lead.public_send(field) == value }
      lead.update!(changes) if changes.any?
      write_event(lead, 'lead_enriquecido', campos: facts.keys) if facts.keys.intersect?(changes.keys)

      warnings = apply_decisao(lead, decisao)
      { ok: true, campos_atualizados: changes.keys, ignorados: ignored, avisos: warnings }
    end

    # [{campo => valor válido}, [chaves ignoradas]]
    def extracted_facts
      raw = @saida['dados_extraidos'].is_a?(Hash) ? @saida['dados_extraidos'].stringify_keys : {}
      ignored = []
      facts = raw.each_with_object({}) do |(field, value), acc|
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        coerced = coerce(field, value)
        if coerced.nil?
          ignored << field
        else
          acc[field] = coerced
        end
      end
      [facts, ignored]
    end

    def coerce(field, value)
      case field
      when *TEXT_FACTS then coerce_text(value)
      when *ENUM_FACTS.keys then ENUM_FACTS[field].include?(value) ? value : nil
      when *NUMERIC_FACTS then coerce_number(value)&.then { |number| BigDecimal(number.to_s) }
      when *INTEGER_FACTS then coerce_integer(value)
      end
    end

    def coerce_text(value)
      value.strip.first(TEXT_MAX).presence if value.is_a?(String)
    end

    def coerce_number(value)
      number = Float(value.to_s)
      number if number >= 0
    rescue ArgumentError, TypeError
      nil
    end

    def coerce_integer(value)
      value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
    end

    def continuity_changes
      {}.tap do |changes|
        changes['aguardando_resposta'] = @saida['aguardando_resposta'] if [true, false].include?(@saida['aguardando_resposta'])
        %w[ultimo_ponto resumo_oportunidade].each do |field|
          value = @saida[field]
          changes[field] = value.strip.first(TEXT_MAX) if value.is_a?(String) && value.strip.present?
        end
      end
    end

    def apply_decisao(lead, decisao)
      case decisao
      when 'qualificado' then OperationalEngine::QualificationService.qualificar!(lead, source: 'lavinia')
      when 'nao_qualificado' then return disqualify(lead)
      when 'em_qualificacao', 'nao_concluido' then progress(lead, decisao)
      end
      []
    end

    # Encerramento por não qualificado já pedido como ação no mesmo turno fica com a ação
    # (CloseAsUnqualifiedService) -- um fato, um evento.
    def disqualify(lead)
      return [] if @saida['acao_sugerida'] == 'encerrar_nao_qualificado'
      return ['nao_qualificado ignorado: lead tem reunião confirmada'] if lead.agendamento_status_confirmado?
      return [] if lead.qualificacao_status_nao_qualificado? && lead.lead_status_encerrado?

      lead.update!(qualificacao_status: 'nao_qualificado', lead_status: 'encerrado', motivo_encerramento: 'nao_qualificado')
      write_event(lead, 'lead_nao_qualificado')
      []
    end

    def progress(lead, decisao)
      return if lead.qualificacao_status_qualificado? || lead.qualificacao_status_nao_qualificado?
      return if lead.qualificacao_status == decisao

      lead.update!(qualificacao_status: decisao)
      write_event(lead, 'qualificacao_iniciada') if decisao == 'em_qualificacao'
    end

    def write_event(lead, event_type, **metadata)
      OperationalEngine::LeadEvent.create!(lead: lead, event_type: event_type, source: 'lavinia',
                                            metadata: metadata.merge(correlation_id: SecureRandom.uuid))
    end
  end
end
