require 'rails_helper'

RSpec.describe Sales::Leads::CreateService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let!(:first_stage) { create(:sales_stage, pipeline: pipeline) }
  let!(:second_stage) { create(:sales_stage, pipeline: pipeline) }

  describe '#perform' do
    it 'creates a lead linked to the given contact and pipeline' do
      lead = described_class.new(account: account, params: { contact_id: contact.id, pipeline_id: pipeline.id, title: 'Negocio novo' }).perform

      expect(lead).to be_persisted
      expect(lead.contact).to eq(contact)
      expect(lead.pipeline).to eq(pipeline)
      expect(lead.title).to eq('Negocio novo')
    end

    it 'defaults to the pipeline first stage when sales_stage_id is not given' do
      lead = described_class.new(account: account, params: { contact_id: contact.id, pipeline_id: pipeline.id, title: 'Negocio novo' }).perform

      expect(lead.stage).to eq(first_stage)
    end

    it 'uses the given stage when sales_stage_id is provided' do
      target_stage = second_stage

      lead = described_class.new(
        account: account,
        params: { contact_id: contact.id, pipeline_id: pipeline.id, sales_stage_id: target_stage.id, title: 'Negocio novo' }
      ).perform

      expect(lead.stage).to eq(target_stage)
    end

    it 'raises when the contact does not belong to the account' do
      other_contact = create(:contact, account: create(:account))

      expect do
        described_class.new(account: account, params: { contact_id: other_contact.id, pipeline_id: pipeline.id, title: 'x' }).perform
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
