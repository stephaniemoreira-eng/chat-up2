FactoryBot.define do
  factory :sales_activity, class: 'Sales::Activity' do
    lead { create(:sales_lead) }
    activity_type { :summary_updated }
    body { 'Resumo atualizado' }
  end
end
