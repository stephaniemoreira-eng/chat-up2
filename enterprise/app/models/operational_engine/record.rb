# Second ActiveRecord connection, declared in code rather than database.yml so that
# `db:schema:dump` never touches it (a second schema file would break the fork's
# `schema-consistency` CI job). This is the Supabase Postgres holding `leads` and
# `lead_events` -- the business-state source of truth (Contrato Técnico do Marco 1, §5.1).
# Everything in `Sales::*` is a projection of what lives here; nothing here reads from there.
module OperationalEngine
  class Record < ActiveRecord::Base
    self.abstract_class = true

    establish_connection(ENV.fetch('OPERATIONAL_ENGINE_DATABASE_URL'))
  end
end
