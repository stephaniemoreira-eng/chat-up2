# == Schema Information
#
# Table name: sales_pipelines
#
#  id          :bigint           not null, primary key
#  active      :boolean          default(TRUE), not null
#  description :text
#  engine_kind :string
#  is_default  :boolean          default(FALSE), not null
#  name        :string           not null
#  position    :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_sales_pipelines_on_account_id                 (account_id)
#  index_sales_pipelines_on_account_id_and_default     (account_id) UNIQUE WHERE (is_default = true)
#  index_sales_pipelines_on_account_id_and_engine_kind  (account_id,engine_kind) UNIQUE WHERE (engine_kind IS NOT NULL)
#  index_sales_pipelines_on_account_id_and_position    (account_id,position)
#
class Sales::Pipeline < ApplicationRecord
  self.table_name = 'sales_pipelines'

  # Pipelines geridos pelo Operational Engine (Fase 5: 'prospect'; Fase 9: 'comercial') -- nunca
  # setado pela UI, só pelos seed services em enterprise/app/services/sales/pipelines/. Existe
  # pra não depender de `name`/`is_default`, que um usuário pode editar/reatribuir livremente.
  ENGINE_KINDS = %w[prospect comercial].freeze

  belongs_to :account
  has_many :stages, -> { order(:position) }, class_name: 'Sales::Stage', foreign_key: :sales_pipeline_id, dependent: :destroy, inverse_of: :pipeline
  has_many :leads, class_name: 'Sales::Lead', foreign_key: :sales_pipeline_id, dependent: :restrict_with_error, inverse_of: :pipeline

  validates :account_id, presence: true
  validates :name, presence: true
  validates :engine_kind, inclusion: { in: ENGINE_KINDS }, allow_nil: true
  validate :single_default_pipeline_per_account, if: :is_default?
  validate :single_pipeline_per_engine_kind_per_account, if: :engine_kind?

  before_create :assign_position

  scope :ordered, -> { order(:position) }
  scope :active, -> { where(active: true) }

  def self.update_positions(account:, positions_hash:)
    return if positions_hash.blank?

    transaction do
      positions_hash.each do |pipeline_id, new_position|
        account.sales_pipelines.find(pipeline_id).update!(position: new_position)
      end
    end
  end

  private

  def assign_position
    return if position.present?

    self.position = (account.sales_pipelines.maximum(:position) || -1) + 1
  end

  def single_default_pipeline_per_account
    return unless account.sales_pipelines.where(is_default: true).where.not(id: id).exists?

    errors.add(:is_default, 'already exists for this account')
  end

  def single_pipeline_per_engine_kind_per_account
    return if account.nil?
    return unless account.sales_pipelines.where(engine_kind: engine_kind).where.not(id: id).exists?

    errors.add(:engine_kind, 'already assigned to another pipeline for this account')
  end
end
