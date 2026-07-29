FactoryBot.define do
  factory :sales_lead, class: 'Sales::Lead' do
    sequence(:title) { |n| "Lead #{n}" }
    account { pipeline&.account || create(:account) }
    contact { create(:contact, account: account) }
    pipeline factory: :sales_pipeline
    stage { pipeline.stages.first || create(:sales_stage, pipeline: pipeline) }
  end
end
