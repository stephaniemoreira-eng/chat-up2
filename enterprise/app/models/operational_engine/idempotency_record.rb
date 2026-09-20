# Ledger de idempotência do §5.5. Não é acionado diretamente pelo código de negócio -- ver
# OperationalEngine::IdempotencyGuard, que é quem cria/atualiza estes registros.
module OperationalEngine
  class IdempotencyRecord < OperationalEngine::Record
    self.table_name = 'idempotency_records'
    self.primary_key = 'idempotency_record_id'

    enum :status, %w[received processed error].index_by(&:itself), validate: true, prefix: true

    validates :conta_id, :event_type, :external_source, :external_id, :correlation_id, presence: true
    validates :external_id, uniqueness: { scope: %i[conta_id event_type external_source] }
  end
end
