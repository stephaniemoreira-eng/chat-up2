# Dedup do §5.5 e teste 28.9: a garantia é a constraint UNIQUE da migration, não este código --
# aqui só traduzimos a violação em "evento duplicado, não repete o trabalho" em vez de deixar o
# StatementInvalid do Postgres estourar pra quem chamou.
module OperationalEngine
  class IdempotencyGuard
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
        result = yield(@correlation_id)
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
      Rails.logger.info(
        "[OperationalEngine] duplicate event ignored: conta_id=#{@conta_id} event_type=#{@event_type} " \
        "external_source=#{@external_source} external_id=#{@external_id}"
      )
      nil
    end
  end
end
