require 'rails_helper'

RSpec.describe Sales::Pipelines::SeedDefaultService do
  let(:account) { create(:account) }

  describe '#perform' do
    it 'creates a default pipeline named Comercial' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline).to be_is_default
      expect(pipeline.name).to eq('Comercial')
      expect(pipeline.account).to eq(account)
    end

    it 'creates the six default stages in order' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline.stages.ordered.pluck(:name)).to eq(%w[New Qualified Proposal Negotiation Won Lost])
    end

    it 'assigns the open/won/lost categories correctly' do
      pipeline = described_class.new(account: account).perform
      stages_by_name = pipeline.stages.index_by(&:name)

      expect(stages_by_name['New']).to be_open
      expect(stages_by_name['Won']).to be_won
      expect(stages_by_name['Lost']).to be_lost
    end

    it 'is idempotent when a default pipeline already exists' do
      existing = create(:sales_pipeline, :default, account: account)

      expect { described_class.new(account: account).perform }.not_to change(Sales::Pipeline, :count)
      expect(described_class.new(account: account).perform).to eq(existing)
    end

    it 'does not create stages when returning an existing default pipeline' do
      create(:sales_pipeline, :default, account: account)

      expect { described_class.new(account: account).perform }.not_to change(Sales::Stage, :count)
    end
  end
end
