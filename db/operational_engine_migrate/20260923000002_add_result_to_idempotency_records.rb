# CP-03 (P1-021-01/P1-021-02; SSOT §23.1): o ledger de idempotência passa a guardar o RESULTADO
# lógico do turno (ok/recusado + motivo). Replay do mesmo turno devolve exatamente o que o primeiro
# processamento respondeu -- inclusive uma recusa -- sem reaplicar a mutação, mesmo que o estado
# tenha mudado legitimamente no meio. Aditiva: linhas antigas ficam com result NULL.
class AddResultToIdempotencyRecords < OperationalEngine::Migration
  def up
    add_column :idempotency_records, :result, :jsonb
  end

  def down
    remove_column :idempotency_records, :result
  end
end
