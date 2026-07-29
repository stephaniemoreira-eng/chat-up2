FactoryBot.define do
  factory :sales_lead_conversation, class: 'Sales::LeadConversation' do
    lead { create(:sales_lead) }
    conversation { create(:conversation, account: lead.account) }
  end
end
