# == Schema Information
#
# Table name: sales_leads
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb            not null
#  closed_at             :datetime
#  custom_attributes     :jsonb            not null
#  expected_close_date   :date
#  last_activity_at      :datetime
#  notes                 :text
#  position              :decimal(20, 10)  not null
#  probability           :integer
#  source                :string
#  stage_changed_at      :datetime
#  status                :integer          default("open"), not null
#  title                 :string           not null
#  value                 :decimal(14, 2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  assignee_id           :bigint
#  contact_id            :bigint           not null
#  sales_pipeline_id     :bigint           not null
#  sales_stage_id        :bigint           not null
#
# Indexes
#
#  index_sales_leads_on_account_id                       (account_id)
#  index_sales_leads_on_account_pipeline_stage_position  (account_id,sales_pipeline_id,sales_stage_id,position)
#  index_sales_leads_on_assignee_id                      (assignee_id)
#  index_sales_leads_on_contact_id                       (contact_id)
#
class Sales::Lead < ApplicationRecord
  self.table_name = 'sales_leads'

  include Labelable

  belongs_to :account
  belongs_to :contact
  belongs_to :pipeline, class_name: 'Sales::Pipeline', foreign_key: :sales_pipeline_id, inverse_of: :leads
  belongs_to :stage, class_name: 'Sales::Stage', foreign_key: :sales_stage_id, inverse_of: :leads
  belongs_to :assignee, class_name: 'User', optional: true

  has_many :lead_conversations, class_name: 'Sales::LeadConversation', foreign_key: :sales_lead_id, dependent: :destroy, inverse_of: :lead
  has_many :conversations, through: :lead_conversations
  has_many :stage_transitions, -> { order(created_at: :desc) }, class_name: 'Sales::StageTransition', foreign_key: :sales_lead_id,
                                                                dependent: :destroy, inverse_of: :lead

  enum status: { open: 0, won: 1, lost: 2 }

  delegate :name, :email, :phone_number, :company, to: :contact, allow_nil: true

  validates :account_id, presence: true
  validates :title, presence: true
  validate :pipeline_belongs_to_account
  validate :stage_belongs_to_pipeline

  before_validation :assign_account_from_pipeline
  before_create :assign_position
  before_create :assign_stage_changed_at

  after_create_commit :dispatch_created
  after_update_commit :dispatch_updated, if: :saved_change_to_lead_attributes?

  scope :ordered, -> { order(:position) }

  private

  def assign_account_from_pipeline
    self.account_id ||= pipeline&.account_id
  end

  def pipeline_belongs_to_account
    return if pipeline.nil? || account.nil?

    errors.add(:sales_pipeline_id, 'must belong to the lead account') if pipeline.account_id != account_id
  end

  def stage_belongs_to_pipeline
    return if stage.nil? || pipeline.nil?

    errors.add(:sales_stage_id, 'must belong to the lead pipeline') if stage.sales_pipeline_id != pipeline.id
  end

  def assign_position
    return if position.present?

    self.position = (Sales::Lead.where(sales_stage_id: sales_stage_id).maximum(:position) || -1) + 1
  end

  def assign_stage_changed_at
    self.stage_changed_at ||= Time.current
  end

  def saved_change_to_lead_attributes?
    (saved_changes.keys - %w[updated_at]).any?
  end

  def dispatch_created
    dispatch_event(Events::Types::SALES_LEAD_CREATED)
  end

  def dispatch_updated
    dispatch_event(Events::Types::SALES_LEAD_UPDATED)
  end

  def dispatch_event(event_name)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, sales_lead: self, performed_by: Current.executed_by)
  end
end
