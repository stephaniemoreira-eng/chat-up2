require 'rails_helper'

RSpec.describe Sales::Prospecting::CreateLeadsFromResultsService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:stage) { create(:sales_stage, pipeline: pipeline) }
  let(:search) { account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP') }
  let(:result) { search.results.create!(account: account, place_id: 'p1', name: 'Clinica X', phone_number: '+5513999999999') }

  describe '#perform' do
    it 'does not enqueue a scan when the account has not opted in' do
      expect do
        described_class.new(account: account, pipeline_id: pipeline.id, sales_stage_id: stage.id, result_ids: [result.id]).perform
      end.not_to have_enqueued_job(Sales::Prospecting::ScanResultJob)
    end

    it 'enqueues a scan for the new lead when the account opted into sales_scan' do
      account.enable_features!(:sales_scan)

      expect do
        described_class.new(account: account, pipeline_id: pipeline.id, sales_stage_id: stage.id, result_ids: [result.id]).perform
      end.to have_enqueued_job(Sales::Prospecting::ScanResultJob).with(result.id)
    end
  end
end
