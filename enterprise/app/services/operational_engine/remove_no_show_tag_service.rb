# CP-05 (P2-025-03; SSOT §20.3 "No MVP, a tag pode ser removida manualmente após
# tratamento/remarcação. O evento permanece para sempre.", §28.39).
#
# A tag NO-SHOW é derivada de `no_show_em` (ComercialProjectionSync#computed_tags) -- editar a tag
# direto no card não resolve (a próxima sincronização a devolveria, e o CRM não pode redefinir
# estado, §28.39). A remoção passa pelo Engine: limpa só o campo que controla a representação
# visual corrente e grava um evento próprio. Os eventos `reuniao_no_show` já gravados continuam
# intactos -- `lead_events` é append-only (§7.2, trigger no banco).
#
# Idempotente: sem NO-SHOW corrente não há o que remover -- no-op sem evento (repara projeção
# pendente, se houver).
module OperationalEngine
  class RemoveNoShowTagService
    def self.call!(lead:, user_id:)
      new(lead, user_id).call!
    end

    def initialize(lead, user_id)
      @lead = lead
      @user_id = user_id
    end

    def call!
      @lead.with_lock do
        next if @lead.no_show_em.nil?

        no_show_em = @lead.no_show_em
        @lead.update!(no_show_em: nil)
        write_event(no_show_em)
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'no_show_tag_removida')
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    private

    def write_event(no_show_em)
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: 'no_show_tag_removida', source: 'human',
        metadata: { no_show_em: no_show_em.iso8601, motivo: 'tratamento_ou_remarcacao', responsavel_atual_id: @user_id,
                    correlation_id: SecureRandom.uuid }
      )
    end
  end
end
