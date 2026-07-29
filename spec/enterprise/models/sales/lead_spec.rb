require 'rails_helper'

RSpec.describe Sales::Lead, type: :model do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:stage) { create(:sales_stage, pipeline: pipeline) }
  let(:contact) { create(:contact, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }

    it 'is invalid when the stage does not belong to the lead pipeline' do
      other_pipeline_stage = create(:sales_stage, pipeline: create(:sales_pipeline, account: account))
      lead = build(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: other_pipeline_stage)

      expect(lead).not_to be_valid
      expect(lead.errors[:sales_stage_id]).to be_present
    end

    it 'is invalid when the pipeline does not belong to the lead account' do
      other_account_pipeline = create(:sales_pipeline, account: create(:account))
      other_account_stage = create(:sales_stage, pipeline: other_account_pipeline)
      lead = build(:sales_lead, account: account, contact: contact, pipeline: other_account_pipeline, stage: other_account_stage)

      expect(lead).not_to be_valid
      expect(lead.errors[:sales_pipeline_id]).to be_present
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:assignee).class_name('User').optional }
    it { is_expected.to have_many(:lead_conversations).class_name('Sales::LeadConversation').dependent(:destroy) }
    it { is_expected.to have_many(:conversations).through(:lead_conversations) }
    it { is_expected.to have_many(:stage_transitions).class_name('Sales::StageTransition').dependent(:destroy) }
  end

  describe 'delegation to contact' do
    it 'delegates name, email, phone_number and company' do
      contact.update!(name: 'Ana Souza', email: 'ana@example.com', phone_number: '+5511999999999')
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)

      expect(lead.name).to eq('Ana Souza')
      expect(lead.email).to eq('ana@example.com')
      expect(lead.phone_number).to eq('+5511999999999')
    end
  end

  describe 'status enum' do
    it 'defaults to open' do
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
      expect(lead.status).to eq('open')
    end
  end

  describe 'position assignment' do
    it 'appends new leads to the end of the stage scope' do
      first = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
      second = create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline, stage: stage)

      expect(first.position).to eq(0)
      expect(second.position).to eq(1)
    end

    it 'scopes position sequencing per stage' do
      create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
      other_stage = create(:sales_stage, pipeline: pipeline)
      other_stage_lead = create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline, stage: other_stage)

      expect(other_stage_lead.position).to eq(0)
    end
  end

  describe 'stage_changed_at assignment' do
    it 'sets stage_changed_at on create' do
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
      expect(lead.stage_changed_at).to be_present
    end
  end

  describe 'event dispatch' do
    it 'dispatches sales_lead.created on create' do
      stage # force account/pipeline/stage creation before setting the expectation below

      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::SALES_LEAD_CREATED, anything, hash_including(:sales_lead))

      create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
    end

    it 'dispatches sales_lead.updated on update' do
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)

      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::SALES_LEAD_UPDATED, anything, hash_including(:sales_lead))

      lead.update!(title: 'Updated title')
    end

    it 'does not dispatch sales_lead.updated when only updated_at would change' do
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)

      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with(Events::Types::SALES_LEAD_UPDATED, any_args)

      lead.touch # rubocop:disable Rails/SkipsModelValidations
    end
  end

  describe 'Labelable' do
    it 'supports label assignment' do
      lead = create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: stage)
      lead.update_labels(%w[hot-lead referral])

      expect(lead.reload.label_list).to contain_exactly('hot-lead', 'referral')
    end
  end
end
