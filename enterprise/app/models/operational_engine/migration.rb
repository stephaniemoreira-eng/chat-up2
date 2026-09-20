# ActiveRecord::Migration's DDL helpers (create_table, add_index, execute...) delegate to
# `connection`, which Rails defaults to ActiveRecord::Base.connection -- the PRIMARY Chatwoot
# database. Every migration under db/operational_engine_migrate/ must inherit from this instead
# of ActiveRecord::Migration directly, or its DDL silently runs against the wrong database.
module OperationalEngine
  class Migration < ActiveRecord::Migration[7.1]
    def connection
      OperationalEngine::Record.connection
    end
  end
end
