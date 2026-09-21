# Dedup do §5.5 e teste 28.9: a garantia é a constraint UNIQUE da migration, não este código --
# aqui só traduzimos a violação em "evento duplicado, não repete o trabalho" em vez de deixar o
# StatementInvalid do Postgres estourar pra quem chamou.
module OperationalEngine
  class IdempotencyGuard
    MAX_ATTEMPTS = 3
    def self.call(**kwargs, &block)
      new(**kwargs).call(&block)
    end

    def initialize(conta_id:, event_type:, external_source:, external_id:)
      @conta_id = conta_id
      @event_type = event_type
      @external_source = external_source
      @external_id = external_id
      @correlation_id = SecureRandom.uuid
    end

    def call
      record = create_record_or_detect_duplicate
      return nil if record.nil?

      begin
        result = yield(record.correlation_id)
        record.update!(status: 'processed', processed_at: Time.current)
        result
      rescue StandardError => e
        record.update!(status: 'error', error_message: e.message)
        raise
      end
    end

    private

    def create_record_or_detect_duplicate
      OperationalEngine::IdempotencyRecord.create!(
        conta_id: @conta_id,
        event_type: @event_type,
        external_source: @external_source,
        external_id: @external_id,
        correlation_id: @correlation_id
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      existing = OperationalEngine::IdempotencyRecord.find_by(
        conta_id: @conta_id,
        event_type: @event_type,
        external_source: @external_source,
        external_id: @external_id
      )
      return retry_failed_record(existing) if existing&.status_error?

      Rails.logger.info(
        "[OperationalEngine] duplicate event ignored: conta_id=#{@conta_id} event_type=#{@event_type} " \
        "external_source=#{@external_source} external_id=#{@external_id}"
      )
      nil
    end

    # Falhas transitórias não podem transformar um fato externo em "para sempre ignorado". O
    # claim é atômico: somente um worker reabre o registro `error`; os demais continuam vendo o
    # evento como já em processamento. Depois de três tentativas ele permanece `error`, visível
    # para operação e para reprocessamento consciente, sem retry infinito (§23.3).
    def retry_failed_record(record)
      return nil if record.attempts >= MAX_ATTEMPTS

      claimed = OperationalEngine::IdempotencyRecord.where(
        idempotency_record_id: record.idempotency_record_id,
        status: 'error'
      ).where('attempts < ?', MAX_ATTEMPTS).update_all(
        status: 'received',
        attempts: record.attempts + 1,
        error_message: nil,
        updated_at: Time.current
      )
      return nil if claimed.zero?

      record.reload
    end
  end
end
