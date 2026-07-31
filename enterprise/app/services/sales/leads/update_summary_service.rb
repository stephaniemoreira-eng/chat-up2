class Sales::Leads::UpdateSummaryService
  def initialize(lead:, summary:, user: nil)
    @lead = lead
    @summary = summary
    @user = user
  end

  def perform
    ActiveRecord::Base.transaction do
      @lead.activities.create!(
        account: @lead.account,
        activity_type: :summary_updated,
        body: @summary,
        user: @user
      )
      @lead.update!(summary: @summary, last_activity_at: Time.current)
    end

    @lead
  end
end
