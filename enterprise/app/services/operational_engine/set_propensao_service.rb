# Fase 9 (§20.2): propensão FRIO/MORNO/QUENTE é "classificação humana/manual do Comercial no
# MVP -- Lavínia não deve inferi-la automaticamente" -- então este serviço só existe pro lado
# humano (não há tool equivalente pro Engine/IA chamar).
#
# Idempotente de propósito, mesmo padrão de TakeoverService: reclassificar pro mesmo valor que já
# está gravado não é erro, é um no-op que não duplica evento nem re-sincroniza à toa.
module OperationalEngine
  class SetPropensaoService
    def self.call!(lead:, propensao:, user_id:)
      new(lead, propensao, user_id).call!
    end

    def initialize(lead, propensao, user_id)
      @lead = lead
      @propensao = propensao
      @user_id = user_id
    end

    def call!
      changed = false

      @lead.with_lock do
        next if @lead.propensao_fechamento == @propensao

        @lead.update!(propensao_fechamento: @propensao)
        write_event
        changed = true
      end

      sync! if changed
      @lead
    end

    private

    def write_event
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: 'propensao_atualizada', source: 'human',
        metadata: { propensao_fechamento: @propensao, responsavel_atual_id: @user_id, correlation_id: SecureRandom.uuid }
      )
    end

    def sync!
      OperationalEngine::SalesProjectionSync.call(@lead)
      OperationalEngine::ComercialProjectionSync.call(@lead)
    end
  end
end
