# == Schema Information
#
# Table name: sales_stages
#
#  id                :bigint           not null, primary key
#  category          :integer          default("open"), not null
#  color             :string
#  name              :string           not null
#  position          :integer          not null
#  probability       :integer
#  stale_after_hours :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  sales_pipeline_id :bigint           not null
#
# Indexes
#
#  index_sales_stages_on_account_id                      (account_id)
#  index_sales_stages_on_sales_pipeline_id               (sales_pipeline_id)
#  index_sales_stages_on_sales_pipeline_id_and_position  (sales_pipeline_id,position)
#
class Sales::Stage < ApplicationRecord
  self.table_name = 'sales_stages'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Sales::Pipeline', foreign_key: :sales_pipeline_id, inverse_of: :stages
  has_many :leads, class_name: 'Sales::Lead', foreign_key: :sales_stage_id, dependent: :restrict_with_error, inverse_of: :stage

  enum category: { open: 0, won: 1, lost: 2 }

  validates :account_id, presence: true
  validates :name, presence: true
  validates :probability, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :stale_after_hours, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  before_validation :assign_account_from_pipeline
  before_create :assign_position
  before_destroy :ensure_not_last_stage_in_pipeline

  scope :ordered, -> { order(:position) }

  def self.update_positions(pipeline:, positions_hash:)
    return if positions_hash.blank?

    transaction do
      positions_hash.each do |stage_id, new_position|
        pipeline.stages.find(stage_id).update!(position: new_position)
      end
    end
  end

  private

  def assign_account_from_pipeline
    self.account_id ||= pipeline&.account_id
  end

  def assign_position
    return if position.present?

    self.position = (pipeline.stages.maximum(:position) || -1) + 1
  end

  # A pipeline with zero stages breaks every consumer that assumes one exists (Follow-up sync's
  # default_stage, prospecting's create_leads default, the CRM board itself) -- some of those
  # consumers fail loudly, but at least one (prospecting) was silently swallowing the resulting
  # RecordInvalid and returning success with zero leads created. Block the underlying cause instead
  # of chasing each symptom.
  def ensure_not_last_stage_in_pipeline
    # Skip when this stage is being removed as part of the pipeline's own `dependent: :destroy`
    # cascade (Sales::Pipeline#stages) -- the whole pipeline is going away anyway, so a pipeline
    # with a single stage must still be deletable. `destroyed_by_association` is exactly the flag
    # Rails sets for this case. Only a standalone "delete this one stage" is what this guards.
    return if destroyed_by_association
    return if pipeline.stages.where.not(id: id).exists?

    errors.add(:base, 'cannot delete the last stage of a pipeline')
    throw :abort
  end
end
