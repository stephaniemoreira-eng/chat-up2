# Fase 9 (§20.2): propensão FRIO/MORNO/QUENTE é "classificação humana/manual do Comercial no
# MVP -- Lavínia não deve inferi-la automaticamente" -- então este serviço só existe pro lado
# humano (não há tool equivalente pro Engine/IA chamar).
#
# Idempotente de propósito, mesmo padrão de TakeoverService: reclassificar pro mesmo valor que já
# está gravado não é erro, é um no-op que não duplica evento (mas repara uma projeção que tenha
# ficado pendente -- CP-05, P1-025-04).
#
# CP-05 (P1-025-02): só sobre uma oportunidade Comercial aberta (OperationalEngine::ComercialActionGuard),
# guarda avaliada dentro do lock -- vale mesmo para chamada direta por API.
module OperationalEngine
  class SetPropensaoService
    class InvalidPropensaoError < StandardError; end

    def self.call!(lead:, propensao:, user_id:)
      new(lead, propensao, user_id).call!
    end

    def initialize(lead, propensao, user_id)
      @lead = lead
      @propensao = propensao
      @user_id = user_id
    end

    def call!
      unless OperationalEngine::Lead.propensao_fechamentos.key?(@propensao)
        raise InvalidPropensaoError, "propensão inválida: #{@propensao.inspect}"
      end

      @lead.with_lock do
        OperationalEngine::ComercialActionGuard.ensure_oportunidade_aberta!(@lead, acao: 'classificar propensão')
        next if @lead.propensao_fechamento == @propensao

        previous = @lead.propensao_fechamento
        @lead.update!(propensao_fechamento: @propensao)
        write_event(previous)
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'propensao_atualizada')
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    private

    def write_event(previous)
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: 'propensao_atualizada', source: 'human',
        metadata: { de: previous, para: @propensao, propensao_fechamento: @propensao, responsavel_atual_id: @user_id,
                    correlation_id: SecureRandom.uuid }
      )
    end
  end
end
