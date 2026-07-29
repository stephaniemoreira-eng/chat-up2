require 'rails_helper'

RSpec.describe Sales::Pipeline, type: :model do
  let(:account) { create(:account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'is invalid without an account' do
      pipeline = build(:sales_pipeline, account: nil)
      expect(pipeline).not_to be_valid
      expect(pipeline.errors[:account_id]).to be_present
    end

    it 'allows only one default pipeline per account' do
      create(:sales_pipeline, :default, account: account)
      second = build(:sales_pipeline, :default, account: account)

      expect(second).not_to be_valid
      expect(second.errors[:is_default]).to be_present
    end

    it 'allows a default pipeline per account when accounts differ' do
      create(:sales_pipeline, :default, account: account)
      other_account_pipeline = build(:sales_pipeline, :default, account: create(:account))

      expect(other_account_pipeline).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:stages).class_name('Sales::Stage').dependent(:destroy) }
  end

  describe 'position assignment' do
    it 'appends new pipelines to the end of the account scope' do
      first = create(:sales_pipeline, account: account)
      second = create(:sales_pipeline, account: account)

      expect(first.position).to eq(0)
      expect(second.position).to eq(1)
    end

    it 'does not override an explicitly assigned position' do
      pipeline = create(:sales_pipeline, account: account, position: 5)

      expect(pipeline.position).to eq(5)
    end

    it 'scopes position sequencing per account' do
      create(:sales_pipeline, account: account)
      other_account_pipeline = create(:sales_pipeline, account: create(:account))

      expect(other_account_pipeline.position).to eq(0)
    end
  end

  describe '.update_positions' do
    it 'updates positions for the given pipelines' do
      first = create(:sales_pipeline, account: account)
      second = create(:sales_pipeline, account: account)

      described_class.update_positions(account: account, positions_hash: { first.id => 1, second.id => 0 })

      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(0)
    end

    it 'does nothing when positions_hash is blank' do
      pipeline = create(:sales_pipeline, account: account)

      expect { described_class.update_positions(account: account, positions_hash: nil) }
        .not_to(change { pipeline.reload.position })
    end

    it 'does not update pipelines belonging to another account' do
      other_pipeline = create(:sales_pipeline, account: create(:account))

      expect { described_class.update_positions(account: account, positions_hash: { other_pipeline.id => 9 }) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'scopes' do
    it '.active returns only active pipelines' do
      active_pipeline = create(:sales_pipeline, account: account, active: true)
      create(:sales_pipeline, account: account, active: false)

      expect(described_class.active).to contain_exactly(active_pipeline)
    end

    it '.ordered returns pipelines ordered by position' do
      second = create(:sales_pipeline, account: account)
      first = create(:sales_pipeline, account: account, position: -1)

      expect(described_class.ordered).to eq([first, second])
    end
  end
end
