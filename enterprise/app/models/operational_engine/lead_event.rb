# Trajetória append-only do lead (SSOT §7.2) -- reconstrói o histórico completo, nunca é editada
# ou apagada depois de gravada. A garantia vive no banco (trigger em
# db/operational_engine_migrate/20260921000001_create_operational_engine_schema.rb), não só aqui:
# `update`/`destroy` falham no Postgres mesmo se algum código chamar o método Ruby diretamente.
module OperationalEngine
  class LeadEvent < OperationalEngine::Record
    self.table_name = 'lead_events'
    self.primary_key = 'event_id'

    belongs_to :lead, class_name: 'OperationalEngine::Lead', foreign_key: :lead_id, inverse_of: :events

    # Forma nova (nome, valores, **options): a forma antiga `enum coluna: valores` combinada com
    # outras options no mesmo hash e ambigua pro Ruby 3 (kwargs vs. hash posicional).
    # scopes: false porque o scope pro valor "import" definiria LeadEvent.import, colidindo com
    # o metodo de classe que a gem activerecord-import ja define.
    enum :source, %w[system lavinia human commercial import].index_by(&:itself), validate: true, prefix: true, scopes: false

    validates :event_type, presence: true

    def readonly?
      persisted?
    end
  end
end
