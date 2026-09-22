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

        @lead.update!(agendamento_status: 'callback_realizado', callback_realizado_em: Time.current)
        write_event
      end

      sync!
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

    def sync!
      OperationalEngine::SalesProjectionSync.call(@lead)
      OperationalEngine::ComercialProjectionSync.call(@lead)
    end
  end
end
