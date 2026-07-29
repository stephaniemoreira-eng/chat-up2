FactoryBot.define do
  factory :sales_stage_transition, class: 'Sales::StageTransition' do
    lead { create(:sales_lead) }
    to_stage { create(:sales_stage, pipeline: lead.pipeline) }
  end
end
