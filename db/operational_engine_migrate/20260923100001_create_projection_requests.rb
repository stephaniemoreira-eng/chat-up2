# CP-05 (P1-025-04, P1-026-02; SSOT §3.2 "retries controlados e sincronização de cards/tags/
# responsáveis", §3.4, §23.3 "retries devem ser limitados e observáveis", §29.3 "sincronização
# Supabase→UpSales falhando").
#
# Pedido durável de projeção (outbox técnico, não estado de negócio -- §3.4 permite estruturas
# técnicas de fila/jobs fora de `leads`/`lead_events`). Mora no MESMO banco do lead de propósito:
# é gravado dentro da mesma transação (o `lead.with_lock`) que persiste o fato de negócio, então
# não existe janela em que o fato foi confirmado e o pedido de projeção se perdeu. A projeção em si
# (Sales::*, Postgres nativo) continua fora do lock -- ver OperationalEngine::ProjectionReconciler.
#
# Uma linha por lead (a projeção é sempre recalculada a partir da fotografia inteira do lead, então
# N mutações pendentes convergem com UMA sincronização). `version` cresce a cada pedido novo: só a
# tentativa que projetou a versão corrente pode marcar a linha como sincronizada.
class CreateProjectionRequests < OperationalEngine::Migration
  def up
    create_table :projection_requests, id: false do |t|
      t.uuid :lead_id, primary_key: true
      t.bigint :conta_id, null: false
      t.text :status, null: false, default: 'pendente'
      t.integer :version, null: false, default: 1
      t.text :motivo
      t.integer :attempts, null: false, default: 0
      t.timestamptz :next_attempt_at
      t.timestamptz :last_attempt_at
      t.text :last_error
      t.timestamptz :synced_at
      t.timestamptz :created_at, null: false, default: -> { 'now()' }
      t.timestamptz :updated_at, null: false, default: -> { 'now()' }
    end

    add_foreign_key :projection_requests, :leads, column: :lead_id, primary_key: :lead_id, on_delete: :cascade
    add_index :projection_requests, :next_attempt_at, where: "status = 'pendente'", name: 'index_projection_requests_due'
    add_index :projection_requests, :status

    execute <<~SQL
      ALTER TABLE projection_requests ADD CONSTRAINT chk_projection_requests_status
        CHECK (status IN ('pendente', 'sincronizado', 'falhou'));
    SQL
  end

  def down
    drop_table :projection_requests
  end
end
