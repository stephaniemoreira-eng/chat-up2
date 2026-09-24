# Fase 9 (§16.3, §21.2): "registrar callback realizado" -- ação humana de UI, quando Danilo/
# comercial efetivamente faz a ligação que estava com agendamento_status=callback_registrado
# (§16.2, já gravado pela Lavínia via OperationalEngine::Tools::RegisterCallbackService).
#
# Só faz sentido em cima de um callback pendente de verdade -- levanta em vez de aceitar
# silenciosamente um clique fora de hora (ex.: botão clicado duas vezes, ou lead sem callback
# nenhum registrado).
module OperationalEngine
  class RegisterCallbackRealizadoService
    class InvalidTransitionError < StandardError; end

    def self.call!(lead:, user_id:)
      new(lead, user_id).call!
    end

    def initialize(lead, user_id)
      @lead = lead
      @user_id = user_id
    end

    def call!
      @lead.with_lock do
        unless @lead.agendamento_status_callback_registrado?
          raise InvalidTransitionError, 'não há callback pendente registrado para este lead'
        end

        now = Time.current
        # CP-04 (P1-025-01, §16.5/§6.3/§28.17): se ainda não houve conversão, o callback realizado é o
        # primeiro marco -- conversao_em = callback_realizado_em (mesmo instante) e
        # tipo_conversao=callback. Se uma reunião já converteu antes, a conversão é preservada
        # (write-once) e só o fato do callback é registrado.
        @lead.update!(
          agendamento_status: 'callback_realizado', callback_realizado_em: now,
          **(@lead.conversao_em.nil? ? { conversao_em: now, tipo_conversao: 'callback' } : {})
        )
        write_event
        # CP-05 (P1-025-04): projeção durável -- ver OperationalEngine::ProjectionReconciler.
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'callback_realizado')
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    private

    # §16.3: "remover tag CALLBACK" não precisa de código próprio -- a tag é derivada de
    # agendamento_status == 'callback_registrado' (ComercialProjectionSync#computed_tags), que
    # já deixou de ser verdade duas linhas acima.
    def write_event
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: 'callback_realizado', source: 'human',
        metadata: { responsavel_atual_id: @user_id, correlation_id: SecureRandom.uuid }
      )
    end
  end
end
