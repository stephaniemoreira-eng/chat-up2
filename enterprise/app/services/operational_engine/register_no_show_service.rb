# Fase 9 (§20.3, §21.2, teste 28.28): "registrar no-show" -- ação humana de UI quando o lead não
# comparece a uma reunião confirmada. Exceção transversal de propósito: só grava o fato e o
# evento, NUNCA muda etapa_prospect nem marca perda automaticamente (§20.3 é explícito nisso) --
# a decisão do que fazer depois (remarcar, insistir, desistir) fica com o humano.
#
# Sem guarda de "só se houver reunião confirmada": o SSOT não condiciona o registro a um estado
# prévio específico, e mais de um no-show ao longo do tempo (reunião remarcada, no-show de novo)
# é um caso real -- por isso sempre grava um evento novo, nunca é idempotente/no-op.
module OperationalEngine
  class RegisterNoShowService
    def self.call!(lead:, user_id:)
      new(lead, user_id).call!
    end

    def initialize(lead, user_id)
      @lead = lead
      @user_id = user_id
    end

    def call!
      @lead.with_lock do
        @lead.update!(no_show_em: Time.current)
        write_event
      end

      sync!
      @lead
    end

    private

    def write_event
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: 'reuniao_no_show', source: 'human',
        metadata: { responsavel_atual_id: @user_id, correlation_id: SecureRandom.uuid }
      )
    end

    def sync!
      OperationalEngine::SalesProjectionSync.call(@lead)
      OperationalEngine::ComercialProjectionSync.call(@lead)
    end
  end
end
