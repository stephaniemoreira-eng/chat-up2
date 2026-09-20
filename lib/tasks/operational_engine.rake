# Runs migrations from db/operational_engine_migrate/ against the Supabase connection
# (OperationalEngine::Record), completely separate from `rails db:migrate` -- that command
# never sees this path, and `db:schema:dump` never sees this connection. Explicit deploy step
# in Coolify (never implicit), so a schema that hasn't caught up fails loudly instead of the
# app coming up against tables that don't exist yet.
namespace :oe do
  # Rails 7.2 removed Connection#schema_migration (the convenience method that used to build
  # this); building SchemaMigration/InternalMetadata straight from the pool is the replacement --
  # see https://github.com/rails/rails/blob/v7.2.3.1/activerecord/lib/active_record/schema_migration.rb.
  # Both need the pool explicitly, or they'd silently default to ActiveRecord::Base's.
  def operational_engine_migration_context
    pool = OperationalEngine::Record.connection_pool
    ActiveRecord::MigrationContext.new(
      Rails.root.join('db/operational_engine_migrate').to_s,
      ActiveRecord::SchemaMigration.new(pool),
      ActiveRecord::InternalMetadata.new(pool)
    )
  end

  desc 'Run pending Operational Engine (Supabase) migrations'
  task migrate: :environment do
    context = operational_engine_migration_context
    context.migrate
    puts "Operational Engine schema at version #{context.current_version}"
  end

  desc 'Roll back the last Operational Engine (Supabase) migration'
  task rollback: :environment do
    context = operational_engine_migration_context
    context.rollback
    puts "Operational Engine schema at version #{context.current_version}"
  end

  desc 'Verify the Operational Engine connection: transaction, prepared statement, row lock'
  task verify_connection: :environment do
    conn = OperationalEngine::Record.connection
    conn.transaction do
      conn.select_value('SELECT 1')
      raise ActiveRecord::Rollback
    end
    puts "OK: #{OperationalEngine::Record.connection_db_config.database} reachable, " \
         'transaction + prepared statement succeeded.'
  end
end
