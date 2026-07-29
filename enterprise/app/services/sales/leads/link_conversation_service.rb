class Sales::Leads::LinkConversationService
  def initialize(lead:, conversation:)
    @lead = lead
    @conversation = conversation
  end

  def perform
    Sales::LeadConversation.create!(account: @lead.account, lead: @lead, conversation: @conversation)
  end
end
