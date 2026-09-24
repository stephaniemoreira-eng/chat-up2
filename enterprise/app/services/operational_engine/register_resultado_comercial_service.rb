# Fase 9 (§17.4, §21.2): "ganho/perda" -- ação humana de UI que resolve a oportunidade Comercial.
#
# Decisão deliberada de escopo (MVP, §21.3 "não construir CRM comercial completo"): resolução é
# de mão única, sem "desfazer" ou "recorrigir" pelo mesmo endpoint -- levanta em vez de aceitar
# resolver de novo uma oportunidade que já é ganho ou perdido. Corrigir um clique errado é caso
# raro o suficiente pra passar por suporte/console nesta fase, em vez de todo clique carregar o
# risco de sobrescrever silenciosamente um resultado (e um ganho_em) já registrado.
#
# CP-05:
# - P1-025-02: resultado terminal só a partir de uma transição Comercial permitida (§8.4:
#   Em acompanhamento → Ganho/Perdido), validada no Engine dentro do lock
#   (OperationalEngine::ComercialActionGuard) -- não depende do botão estar visível.
# - P1-025-03: Ganho completa o estado de cliente atual (§17.4 + §19.1): motivo_encerramento =
#   cliente_atual junto com relacao_atual/lead_status. Conversão Prospect (conversao_em/
#   tipo_conversao) nunca é tocada aqui -- é fato distinto do resultado (§16.5, §28.30/§28.31).
# - P2-025-02: a timeline preserva cada semântica alterada (§7.4): resultado_ganho/perdido,
#   relacao_atualizada (Ganho) e lead_encerrado, com de/para/motivo (§7.3).
module OperationalEngine
  class RegisterResultadoComercialService
    class AlreadyResolvedError < StandardError; end
    class InvalidResultadoError < StandardError; end

    RESULTADOS_VALIDOS = %w[ganho perdido].freeze
    TRACKED = %i[etapa_comercial resultado_comercial relacao_atual lead_status motivo_encerramento].freeze

    def self.call!(lead:, resultado:, user_id:, motivo_perda: nil)
      new(lead, resultado, user_id, motivo_perda).call!
    end

    def initialize(lead, resultado, user_id, motivo_perda)
      @lead = lead
      @resultado = resultado
      @user_id = user_id
      @motivo_perda = motivo_perda
    end

    def call!
      raise InvalidResultadoError, "resultado inválido: #{@resultado.inspect}" unless RESULTADOS_VALIDOS.include?(@resultado)

      @lead.with_lock do
        if %w[ganho perdido].include?(@lead.resultado_comercial)
          raise AlreadyResolvedError, "oportunidade já foi resolvida como #{@lead.resultado_comercial}"
        end

        OperationalEngine::ComercialActionGuard.ensure_transicao!(@lead, para: @resultado)
        resolve!
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    private

    def resolve!
      before = TRACKED.index_with { |field| @lead.public_send(field) }
      @lead.update!(resolution_attributes)
      write_events(before)
      OperationalEngine::ProjectionReconciler.request!(@lead, motivo: "resultado_#{@resultado}")
    end

    # §17.4: ganho leva ganho_em + relacao_atual=cliente_atual (+ motivo_encerramento, §19.1);
    # perdido leva motivo_perda (opcional, texto livre -- §6.1 já documenta esse campo como
    # não-enum de propósito). Perdido não define motivo_encerramento: o §17.4 não diz qual seria e
    # o enum do §6.2 não tem um valor próprio para "perdido no Comercial" -- não inventamos.
    def resolution_attributes
      attrs = { resultado_comercial: @resultado, etapa_comercial: @resultado, lead_status: 'encerrado' }
      if @resultado == 'ganho'
        attrs.merge!(ganho_em: Time.current, relacao_atual: 'cliente_atual', motivo_encerramento: 'cliente_atual')
      elsif @motivo_perda.present?
        attrs[:motivo_perda] = @motivo_perda
      end
      attrs
    end

    def write_events(before)
      correlation_id = SecureRandom.uuid
      event(@resultado == 'ganho' ? 'resultado_ganho' : 'resultado_perdido', correlation_id,
            de: before[:etapa_comercial], para: @resultado, **(@motivo_perda.present? ? { motivo_perda: @motivo_perda } : {}))
      write_relacao_event(before, correlation_id)
      write_encerramento_event(before, correlation_id)
    end

    def write_relacao_event(before, correlation_id)
      return if before[:relacao_atual] == @lead.relacao_atual

      event('relacao_atualizada', correlation_id, de: before[:relacao_atual], para: @lead.relacao_atual, motivo: 'resultado_ganho')
    end

    def write_encerramento_event(before, correlation_id)
      return if before.values_at(:lead_status, :motivo_encerramento) == [@lead.lead_status, @lead.motivo_encerramento]

      event('lead_encerrado', correlation_id,
            de: before[:lead_status], para: @lead.lead_status, motivo: "resultado_#{@resultado}",
            motivo_encerramento_de: before[:motivo_encerramento], motivo_encerramento: @lead.motivo_encerramento)
    end

    def event(event_type, correlation_id, **metadata)
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: event_type, source: 'human',
        metadata: metadata.merge(responsavel_atual_id: @user_id, correlation_id: correlation_id)
      )
    end
  end
end
