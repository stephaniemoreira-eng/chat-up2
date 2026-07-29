class Sales::Leads::MoveStageService
  def initialize(lead:, stage:, position: nil, user: nil)
    @lead = lead
    @stage = stage
    @position = position
    @user = user
  end

  def perform
    raise ArgumentError, 'stage must belong to the lead pipeline' if @stage.sales_pipeline_id != @lead.sales_pipeline_id
    return @lead if @stage.id == @lead.sales_stage_id

    from_stage = @lead.stage
    stage_changed_at_was = @lead.stage_changed_at

    ActiveRecord::Base.transaction do
      move_lead
      record_transition(from_stage, stage_changed_at_was)
    end

    dispatch_events(from_stage)
    @lead
  end

  private

  def move_lead
    @lead.update!(
      stage: @stage,
      position: @position || next_position,
      stage_changed_at: Time.current,
      status: status_for(@stage),
      closed_at: @stage.open? ? nil : Time.current
    )
  end

  def record_transition(from_stage, stage_changed_at_was)
    Sales::StageTransition.create!(
      account: @lead.account,
      lead: @lead,
      from_stage: from_stage,
      to_stage: @stage,
      user: @user,
      duration_in_previous_stage_seconds: stage_changed_at_was && (Time.current - stage_changed_at_was).round
    )
  end

  def next_position
    (Sales::Lead.where(sales_stage_id: @stage.id).maximum(:position) || -1) + 1
  end

  def status_for(stage)
    return 'won' if stage.won?
    return 'lost' if stage.lost?

    'open'
  end

  def dispatch_events(from_stage)
    dispatch(Events::Types::SALES_LEAD_STAGE_CHANGED, from_stage: from_stage, to_stage: @stage)
    dispatch(Events::Types::SALES_LEAD_WON) if @lead.won?
    dispatch(Events::Types::SALES_LEAD_LOST) if @lead.lost?
  end

  def dispatch(event_name, **extra_payload)
    payload = { sales_lead: @lead, performed_by: Current.executed_by, **extra_payload }
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, **payload)
  end
end
