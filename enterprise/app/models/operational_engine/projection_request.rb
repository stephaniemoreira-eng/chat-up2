# CP-05 (P1-025-04, P1-026-02). Pedido durável de projeção Supabase → Sales::* de um lead. Não é
# estado de negócio (§3.4): é o registro técnico de "a fotografia deste lead mudou e o CRM ainda
# precisa refletir isso". Nunca manipule direto -- use OperationalEngine::ProjectionReconciler.
module OperationalEngine
  class ProjectionRequest < OperationalEngine::Record
    self.table_name = 'projection_requests'
    self.primary_key = 'lead_id'

    enum :status, %w[pendente sincronizado falhou].index_by(&:itself), validate: true, prefix: true

    belongs_to :lead, class_name: 'OperationalEngine::Lead', foreign_key: :lead_id, inverse_of: false

    validates :conta_id, presence: true

    scope :due, ->(now = Time.current) { status_pendente.where('next_attempt_at <= ?', now) }
  end
end
