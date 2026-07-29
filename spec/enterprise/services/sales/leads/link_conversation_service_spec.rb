require 'rails_helper'

RSpec.describe Sales::Leads::LinkConversationService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    it 'links the conversation to the lead' do
      link = described_class.new(lead: lead, conversation: conversation).perform

      expect(link).to be_persisted
      expect(link.account).to eq(account)
      expect(lead.reload.conversations).to include(conversation)
      expect(conversation.reload.sales_lead).to eq(lead)
    end

    it 'raises when the conversation is already linked to another lead' do
      described_class.new(lead: lead, conversation: conversation).perform
      other_lead = create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline)

      expect { described_class.new(lead: other_lead, conversation: conversation).perform }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
