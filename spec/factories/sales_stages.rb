FactoryBot.define do
  factory :sales_stage, class: 'Sales::Stage' do
    sequence(:name) { |n| "Stage #{n}" }
    pipeline factory: :sales_pipeline
    category { :open }

    trait :won do
      category { :won }
      probability { 100 }
    end

    trait :lost do
      category { :lost }
      probability { 0 }
    end
  end
end
