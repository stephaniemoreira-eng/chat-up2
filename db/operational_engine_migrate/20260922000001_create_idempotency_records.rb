# Runs against OPERATIONAL_ENGINE_DATABASE_URL via `rake oe:migrate` -- see
# 20260921000001_create_operational_engine_schema.rb for why this lives outside db/migrate/.
#
# §5.5: the ledger that proves "this external event was already processed" lives here, in
# Supabase, not in Redis -- Redis expires and restarts, and lead_events must be reconstructible
# from durable state alone. Redis stays out of Fase 2 on purpose: the composite unique index
# below already gives correct dedup (a second INSERT for the same key fails, full stop), and a
# Redis lock only trims the wasted work of two concurrent workers racing to be first -- it would
# be a performance optimization layered on top of this, never a correctness requirement.
#
# Key is composite, not external_id alone (§5.5): the same external identifier can legitimately
# collide across domains (a Chatwoot message_id and a Google Calendar event_id are different
# namespaces), so conta_id + event_type + external_source + external_id together is what's unique.
class CreateIdempotencyRecords < OperationalEngine::Migration
  def up
    create_table :idempotency_records, id: false do |t|
      t.uuid :idempotency_record_id, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.bigint :conta_id, null: false
      t.text :event_type, null: false
      t.text :external_source, null: false
      t.text :external_id, null: false
      t.text :status, null: false, default: 'received'
      t.uuid :correlation_id, null: false
      t.integer :attempts, null: false, default: 1
      t.text :error_message
      t.timestamptz :processed_at
      t.timestamptz :created_at, null: false, default: -> { 'now()' }
      t.timestamptz :updated_at, null: false, default: -> { 'now()' }
    end

    add_index :idempotency_records, %i[conta_id event_type external_source external_id],
              unique: true, name: 'index_idempotency_records_on_dedup_key'
    add_index :idempotency_records, :correlation_id
    add_index :idempotency_records, :status

    execute <<~SQL
      ALTER TABLE idempotency_records ADD CONSTRAINT chk_idempotency_records_status
        CHECK (status IN ('received', 'processed', 'error'));
    SQL
  end

  def down
    drop_table :idempotency_records
  end
end
