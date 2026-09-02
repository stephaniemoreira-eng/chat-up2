require 'rails_helper'

RSpec.describe Sales::Stage, type: :model do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it { is_expected.to validate_numericality_of(:probability).only_integer.is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100).allow_nil }
    it { is_expected.to validate_numericality_of(:stale_after_hours).only_integer.is_greater_than(0).allow_nil }

    it 'is invalid without a pipeline' do
      stage = build(:sales_stage, pipeline: nil)
      expect(stage).not_to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:pipeline).class_name('Sales::Pipeline') }
  end

  describe 'category enum' do
    it 'defaults to open' do
      expect(create(:sales_stage, pipeline: pipeline).category).to eq('open')
    end

    it 'supports won and lost' do
      expect(create(:sales_stage, :won, pipeline: pipeline)).to be_won
      expect(create(:sales_stage, :lost, pipeline: pipeline)).to be_lost
    end
  end

  describe 'account assignment' do
    it 'derives account_id from the pipeline when not set' do
      stage = create(:sales_stage, pipeline: pipeline)

      expect(stage.account_id).to eq(pipeline.account_id)
    end

    it 'does not override an explicitly assigned account_id' do
      other_account = create(:account)
      stage = create(:sales_stage, pipeline: pipeline, account_id: other_account.id)

      expect(stage.account_id).to eq(other_account.id)
    end
  end

  describe 'position assignment' do
    it 'appends new stages to the end of the pipeline scope' do
      first = create(:sales_stage, pipeline: pipeline)
      second = create(:sales_stage, pipeline: pipeline)

      expect(first.position).to eq(0)
      expect(second.position).to eq(1)
    end

    it 'scopes position sequencing per pipeline' do
      create(:sales_stage, pipeline: pipeline)
      other_pipeline_stage = create(:sales_stage, pipeline: create(:sales_pipeline, account: account))

      expect(other_pipeline_stage.position).to eq(0)
    end
  end

  describe '.update_positions' do
    it 'updates positions for the given stages' do
      first = create(:sales_stage, pipeline: pipeline)
      second = create(:sales_stage, pipeline: pipeline)

      described_class.update_positions(pipeline: pipeline, positions_hash: { first.id => 1, second.id => 0 })

      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(0)
    end

    it 'does not update stages belonging to another pipeline' do
      other_stage = create(:sales_stage, pipeline: create(:sales_pipeline, account: account))

      expect { described_class.update_positions(pipeline: pipeline, positions_hash: { other_stage.id => 9 }) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'scopes' do
    it '.ordered returns stages ordered by position' do
      second = create(:sales_stage, pipeline: pipeline)
      first = create(:sales_stage, pipeline: pipeline, position: -1)

      expect(described_class.ordered).to eq([first, second])
    end
  end

  describe 'destroying the last stage of a pipeline' do
    it 'is blocked, leaving the pipeline with at least one stage' do
      only_stage = create(:sales_stage, pipeline: pipeline)

      expect { only_stage.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(pipeline.stages.reload).to eq([only_stage])
    end

    it 'is allowed when another stage remains in the pipeline' do
      first = create(:sales_stage, pipeline: pipeline)
      second = create(:sales_stage, pipeline: pipeline)

      expect { first.destroy! }.not_to raise_error
      expect(pipeline.stages.reload).to eq([second])
    end

    it 'does not block deleting the last stage of a DIFFERENT pipeline' do
      only_stage = create(:sales_stage, pipeline: pipeline)
      create(:sales_stage, pipeline: create(:sales_pipeline, account: account))

      expect { only_stage.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end
end
