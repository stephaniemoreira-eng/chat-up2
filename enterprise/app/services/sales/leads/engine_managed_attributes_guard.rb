# CP-09 (P2-VAL-07; SSOT §3.3, §20, teste 28.39): o Postgres nativo do UpSales não pode virar uma
# segunda fonte dos estados de negócio. Num card vinculado ao Operational Engine
# (`operational_lead_id` presente), as chaves de custom_attributes que só a projeção do Engine grava
# (OperationalEngine::SalesProjectionSync / ComercialProjectionSync) não são editáveis pela edição
# livre do card (`PATCH /crm/leads/:id`):
# - uma MUDANÇA numa dessas chaves é recusada (o card não fica com tag errada nem até a próxima sync);
# - reenviar o valor que o card já tem é aceito (ex.: o front mandando o custom_attributes inteiro);
# - o PATCH troca o custom_attributes inteiro, então as chaves do Engine são sempre recolocadas com o
#   valor atual, mesmo que o payload as omita.
# O resto do card (título, notas, valor, responsável, custom_attributes não geridos) continua
# editável. Card sem vínculo com o Engine segue o comportamento nativo, sem restrição.
class Sales::Leads::EngineManagedAttributesGuard
  KEYS = %w[engine_tags engine_filters].freeze

  class ChangeError < StandardError; end

  def self.apply!(lead:, attributes:)
    new(lead, attributes).apply!
  end

  def initialize(lead, attributes)
    @lead = lead
    @attributes = attributes.to_h.with_indifferent_access
  end

  def apply!
    return @attributes if @lead.operational_lead_id.blank? || !@attributes.key?(:custom_attributes)

    incoming = (@attributes[:custom_attributes] || {}).to_h.with_indifferent_access
    changed = KEYS.select { |key| incoming.key?(key) && incoming[key] != current[key] }
    raise ChangeError, "atributos geridos pelo Operational Engine não podem ser editados: #{changed.join(', ')}" if changed.any?

    @attributes.merge(custom_attributes: incoming.except(*KEYS).merge(current.slice(*KEYS)))
  end

  private

  def current
    @current ||= (@lead.custom_attributes || {}).with_indifferent_access
  end
end
