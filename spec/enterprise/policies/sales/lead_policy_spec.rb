require 'rails_helper'

RSpec.describe 'Sales::LeadPolicy', type: :policy do
  subject(:lead_policy) { Sales::LeadPolicy }

  let(:account) { create(:account) }
  let(:pipeline) { create(:sales_pipeline, account: account) }
  let(:stage) { create(:sales_stage, pipeline: pipeline) }
  let(:lead) { create(:sales_lead, account: account, contact: create(:contact, account: account), pipeline: pipeline, stage: stage) }

  let(:administrator) { create(:user) }
  let(:administrator_account_user) { create(:account_user, user: administrator, account: account, role: :administrator) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator_account_user } }

  let(:agent) { create(:user) }
  let(:agent_account_user) { create(:account_user, user: agent, account: account, role: :agent) }
  let(:agent_context) { { user: agent, account: account, account_user: agent_account_user } }

  permissions :index?, :show?, :create?, :update?, :move?, :link_conversation?, :unlink_conversation? do
    it 'permits administrators and agents' do
      expect(lead_policy).to permit(administrator_context, lead)
      expect(lead_policy).to permit(agent_context, lead)
    end
  end

  permissions :destroy? do
    it 'permits administrators' do
      expect(lead_policy).to permit(administrator_context, lead)
    end

    it 'does not permit agents' do
      expect(lead_policy).not_to permit(agent_context, lead)
    end
  end
end
