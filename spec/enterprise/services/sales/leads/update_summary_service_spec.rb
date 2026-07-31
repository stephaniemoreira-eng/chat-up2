require 'rails_helper'

RSpec.describe Sales::Leads::UpdateSummaryService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline) }
  let(:user) { create(:user, account: account) }

  describe '#perform' do
    it 'updates the lead summary' do
      described_class.new(lead: lead, summary: 'Cliente interessado no plano anual', user: user).perform

      expect(lead.reload.summary).to eq('Cliente interessado no plano anual')
    end

    it 'records a summary_updated activity with the summary as body' do
      expect do
        described_class.new(lead: lead, summary: 'Novo resumo', user: user).perform
      end.to change(Sales::Activity, :count).by(1)

      activity = lead.activities.first
      expect(activity).to be_summary_updated
      expect(activity.body).to eq('Novo resumo')
      expect(activity.user).to eq(user)
    end

    it 'keeps every previous summary as its own activity record' do
      described_class.new(lead: lead, summary: 'Primeira versao', user: user).perform
      described_class.new(lead: lead, summary: 'Segunda versao', user: user).perform

      expect(lead.activities.pluck(:body)).to contain_exactly('Primeira versao', 'Segunda versao')
      expect(lead.reload.summary).to eq('Segunda versao')
    end

    it 'touches last_activity_at' do
      travel_to(1.hour.from_now) do
        described_class.new(lead: lead, summary: 'Resumo', user: user).perform
        expect(lead.reload.last_activity_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
