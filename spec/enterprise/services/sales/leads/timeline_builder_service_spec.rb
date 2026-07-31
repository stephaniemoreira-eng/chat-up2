require 'rails_helper'

RSpec.describe Sales::Leads::TimelineBuilderService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline) }
  let(:conversation) { create(:conversation, account: account) }

  before { create(:sales_lead_conversation, lead: lead, conversation: conversation) }

  describe '#perform' do
    it 'merges messages, notes, stage transitions and activities ordered by created_at desc' do
      message = travel_to(4.hours.ago) { create(:message, account: account, conversation: conversation, content: 'Ola') }
      note = travel_to(3.hours.ago) { create(:note, account: account, contact: contact, content: 'Cliente ligou') }
      transition = travel_to(2.hours.ago) { create(:sales_stage_transition, lead: lead, to_stage: create(:sales_stage, pipeline: pipeline)) }
      activity = travel_to(1.hour.ago) { create(:sales_activity, lead: lead, body: 'Resumo atualizado') }

      result = described_class.new(lead: lead).perform

      expect(result[:entries].map { |e| e[:type] }).to eq(%w[activity stage_transition note message])
      expect(result[:entries].map { |e| e[:id] }).to eq([activity.id, transition.id, note.id, message.id])
    end

    it 'excludes activity-type (system) messages from the timeline' do
      create(:message, account: account, conversation: conversation, message_type: :activity, content: 'sistema')
      chat_message = create(:message, account: account, conversation: conversation, content: 'oi')

      result = described_class.new(lead: lead).perform

      expect(result[:entries].map { |e| e[:id] }).to eq([chat_message.id])
    end

    it 'does not include notes from other contacts' do
      create(:note, account: account, contact: create(:contact, account: account))
      own_note = create(:note, account: account, contact: contact)

      result = described_class.new(lead: lead).perform

      expect(result[:entries].map { |e| e[:id] }).to eq([own_note.id])
    end

    it 'paginates using the before cursor' do
      older = travel_to(2.hours.ago) { create(:sales_activity, lead: lead) }
      newer = travel_to(1.hour.ago) { create(:sales_activity, lead: lead) }

      first_page = described_class.new(lead: lead, per_page: 1).perform
      expect(first_page[:entries].map { |e| e[:id] }).to eq([newer.id])

      second_page = described_class.new(lead: lead, before: first_page[:next_before], per_page: 1).perform
      expect(second_page[:entries].map { |e| e[:id] }).to eq([older.id])
    end
  end
end
