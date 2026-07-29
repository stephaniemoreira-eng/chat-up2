require 'rails_helper'

RSpec.describe 'Sales::PipelinePolicy', type: :policy do
  subject(:pipeline_policy) { Sales::PipelinePolicy }

  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }

  let(:administrator) { create(:user) }
  let(:administrator_account_user) { create(:account_user, user: administrator, account: account, role: :administrator) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator_account_user } }

  let(:agent) { create(:user) }
  let(:agent_account_user) { create(:account_user, user: agent, account: account, role: :agent) }
  let(:agent_context) { { user: agent, account: account, account_user: agent_account_user } }

  permissions :index?, :show? do
    it 'permits administrators and agents' do
      expect(pipeline_policy).to permit(administrator_context, pipeline)
      expect(pipeline_policy).to permit(agent_context, pipeline)
    end
  end

  permissions :create?, :update?, :destroy?, :reorder? do
    it 'permits administrators' do
      expect(pipeline_policy).to permit(administrator_context, pipeline)
    end

    it 'does not permit agents' do
      expect(pipeline_policy).not_to permit(agent_context, pipeline)
    end
  end
end
