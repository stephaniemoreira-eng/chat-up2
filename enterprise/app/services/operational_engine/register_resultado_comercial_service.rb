# Fase 9 (§17.4, §21.2): "ganho/perda" -- ação humana de UI que resolve a oportunidade Comercial.
#
# Decisão deliberada de escopo (MVP, §21.3 "não construir CRM comercial completo"): resolução é
# de mão única, sem "desfazer" ou "recorrigir" pelo mesmo endpoint -- levanta em vez de aceitar
# resolver de novo uma oportunidade que já é ganho ou perdido. Corrigir um clique errado é caso
# raro o suficiente pra passar por suporte/console nesta fase, em vez de todo clique carregar o
# risco de sobrescrever silenciosamente um resultado (e um ganho_em) já registrado.
module OperationalEngine
  class RegisterResultadoComercialService
    class AlreadyResolvedError < StandardError; end
    class InvalidResultadoError < StandardError; end

    RESULTADOS_VALIDOS = %w[ganho perdido].freeze

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

        @lead.update!(resolution_attributes)
        write_event
      end

      sync!
      @lead
    end

    private

    # §17.4: ganho leva ganho_em + relacao_atual=cliente_atual; perdido leva motivo_perda
    # (opcional, texto livre -- §6.1 já documenta esse campo como não-enum de propósito).
    def resolution_attributes
      attrs = { resultado_comercial: @resultado, etapa_comercial: @resultado, lead_status: 'encerrado' }
      if @resultado == 'ganho'
        attrs[:ganho_em] = Time.current
        attrs[:relacao_atual] = 'cliente_atual'
      elsif @motivo_perda.present?
        attrs[:motivo_perda] = @motivo_perda
      end
      attrs
    end

    def write_event
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: @resultado == 'ganho' ? 'resultado_ganho' : 'resultado_perdido', source: 'human',
        metadata: { motivo_perda: @motivo_perda, responsavel_atual_id: @user_id, correlation_id: SecureRandom.uuid }.compact
      )
    end

    def sync!
      OperationalEngine::SalesProjectionSync.call(@lead)
      OperationalEngine::ComercialProjectionSync.call(@lead)
    end
  end
end
