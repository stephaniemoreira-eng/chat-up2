require 'rails_helper'

RSpec.describe Sales::Leads::MoveStageService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:open_stage) { create(:sales_stage, pipeline: pipeline) }
  let(:won_stage) { create(:sales_stage, :won, pipeline: pipeline) }
  let(:lost_stage) { create(:sales_stage, :lost, pipeline: pipeline) }
  let(:contact) { create(:contact, account: account) }
  let(:lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: open_stage) }
  let(:user) { create(:user, account: account) }

  describe '#perform' do
    it 'raises when the stage does not belong to the lead pipeline' do
      other_stage = create(:sales_stage, pipeline: create(:sales_pipeline, account: account))

      expect { described_class.new(lead: lead, stage: other_stage).perform }.to raise_error(ArgumentError)
    end

    it 'is a no-op when moving to the current stage' do
      expect { described_class.new(lead: lead, stage: open_stage).perform }.not_to change(Sales::StageTransition, :count)
    end

    it 'updates the lead stage and stage_changed_at' do
      travel_to(1.hour.from_now) do
        moved = described_class.new(lead: lead, stage: won_stage, user: user).perform

        expect(moved.stage).to eq(won_stage)
        expect(moved.stage_changed_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'creates a stage transition recording the previous stage, user and duration' do
      lead # force creation (and its stage_changed_at) at the real current time, before travelling

      travel_to(2.hours.from_now) do
        described_class.new(lead: lead, stage: won_stage, user: user).perform
      end

      transition = lead.stage_transitions.first
      expect(transition.from_stage).to eq(open_stage)
      expect(transition.to_stage).to eq(won_stage)
      expect(transition.user).to eq(user)
      expect(transition.duration_in_previous_stage_seconds).to be_within(1).of(2.hours.to_i)
    end

    it 'sets status to won and closed_at when moved to a won stage' do
      moved = described_class.new(lead: lead, stage: won_stage).perform

      expect(moved).to be_won
      expect(moved.closed_at).to be_present
    end

    it 'sets status to lost and closed_at when moved to a lost stage' do
      moved = described_class.new(lead: lead, stage: lost_stage).perform

      expect(moved).to be_lost
      expect(moved.closed_at).to be_present
    end

    it 'clears closed_at when moved back to an open stage' do
      described_class.new(lead: lead, stage: won_stage).perform
      other_open_stage = create(:sales_stage, pipeline: pipeline)

      moved = described_class.new(lead: lead, stage: other_open_stage).perform

      expect(moved).to be_open
      expect(moved.closed_at).to be_nil
    end

    it 'appends the lead to the end of the destination stage' do
      existing_lead_in_won = create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline, stage: won_stage)

      moved = described_class.new(lead: lead, stage: won_stage).perform

      expect(moved.position).to be > existing_lead_in_won.position
    end

    it 'dispatches the stage changed event' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        Events::Types::SALES_LEAD_STAGE_CHANGED, anything, hash_including(from_stage: open_stage, to_stage: won_stage)
      )

      described_class.new(lead: lead, stage: won_stage).perform
    end

    it 'dispatches the won event when moved to a won stage' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::SALES_LEAD_WON, anything, anything)

      described_class.new(lead: lead, stage: won_stage).perform
    end

    it 'dispatches the lost event when moved to a lost stage' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::SALES_LEAD_LOST, anything, anything)

      described_class.new(lead: lead, stage: lost_stage).perform
    end
  end
end
