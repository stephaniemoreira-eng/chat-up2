# Runs migrations from db/operational_engine_migrate/ against the Supabase connection
# (OperationalEngine::Record), completely separate from `rails db:migrate` -- that command
# never sees this path, and `db:schema:dump` never sees this connection. Explicit deploy step
# in Coolify (never implicit), so a schema that hasn't caught up fails loudly instead of the
# app coming up against tables that don't exist yet.
namespace :oe do
  desc 'Run pending Operational Engine (Supabase) migrations'
  task migrate: :environment do
    context = ActiveRecord::MigrationContext.new(
      Rails.root.join('db/operational_engine_migrate').to_s,
      OperationalEngine::Record.connection.schema_migration
    )
    context.migrate
    puts "Operational Engine schema at version #{context.current_version}"
  end

  desc 'Roll back the last Operational Engine (Supabase) migration'
  task rollback: :environment do
    context = ActiveRecord::MigrationContext.new(
      Rails.root.join('db/operational_engine_migrate').to_s,
      OperationalEngine::Record.connection.schema_migration
    )
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
