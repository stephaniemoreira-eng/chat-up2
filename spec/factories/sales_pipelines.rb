FactoryBot.define do
  factory :sales_pipeline, class: 'Sales::Pipeline' do
    sequence(:name) { |n| "Pipeline #{n}" }
    account

    trait :default do
      is_default { true }
    end
  end
end
