# CP-03 (P1-021-01; SSOT §23.1 "o mesmo evento externo recebido duas vezes não pode produzir duas
# ações"): idempotência das chamadas da Lavínia ao Engine por IDENTIDADE DO TURNO, não por
# conversation_id (que bloquearia ações legítimas futuras na mesma conversa) nem só pelo estado
# atual (que não pega replay tardio depois de uma mudança legítima).
#
# `turn_id` é estável por turno: `msg:<message_id do disparador>` num turno reativo,
# `ativacao:<activation_id>` na primeira abordagem (mesma identidade da OriginationActivation do
# CP-01, que o CP-02 também reutiliza). Chave do ledger = conta + operação + turn_id: um turno pode
# commitar a saída estruturada E pedir uma ação sem que uma bloqueie a outra.
#
# - primeira vez: executa, guarda o resultado lógico e devolve;
# - replay (mesmo turno + mesma operação) já processado: devolve o resultado guardado, sem executar;
# - replay concorrente enquanto o primeiro ainda roda: recusa como "em processamento" (nada roda 2x);
# - execução anterior que estourou exceção: pode ser reexecutada (a mutação não se completou).
#
# Sem turn_id (chamador legado) executa sem ledger -- compatibilidade durante o deploy; o up2-agents
# deste pacote sempre envia.
module OperationalEngine
  class TurnIdempotency
    EXTERNAL_SOURCE = 'lavinia_turn'.freeze
    IN_PROGRESS = { ok: false, reason: 'turno já em processamento' }.freeze

    def self.call(conta_id:, operacao:, turn_id:, &)
      new(conta_id, operacao, turn_id).call(&)
    end

    def initialize(conta_id, operacao, turn_id)
      @conta_id = conta_id
      @operacao = operacao
      @turn_id = turn_id.presence
    end

    def call
      return yield if @turn_id.nil?

      record, mine = claim
      return stored_result(record) unless mine

      begin
        result = yield
        record.update!(status: 'processed', processed_at: Time.current, result: result)
        result
      rescue StandardError => e
        record.update!(status: 'error', error_message: e.message)
        raise
      end
    end

    private

    # [registro, é_meu?]. Criar o registro é a reivindicação (a UNIQUE do ledger garante um só
    # vencedor). Já existindo: processed/received ficam com quem chegou antes; error é retomado --
    # com update condicional, para dois retries simultâneos não retomarem ambos.
    def claim
      [OperationalEngine::IdempotencyRecord.create!(key.merge(correlation_id: SecureRandom.uuid)), true]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      existing = OperationalEngine::IdempotencyRecord.find_by!(key)
      return [existing, false] unless existing.status_error?

      # update condicional atômico de propósito: é ele que decide quem retoma, não uma validação.
      retaken = OperationalEngine::IdempotencyRecord
                .where(idempotency_record_id: existing.idempotency_record_id, status: 'error')
                .update_all(status: 'received', attempts: existing.attempts + 1, error_message: nil) # rubocop:disable Rails/SkipsModelValidations
      [existing.reload, retaken == 1]
    end

    def stored_result(record)
      return IN_PROGRESS.dup if record.status_received?

      (record.result || { ok: true }).deep_symbolize_keys.merge(replay: true)
    end

    def key
      { conta_id: @conta_id, event_type: @operacao, external_source: EXTERNAL_SOURCE, external_id: @turn_id }
    end
  end
end
