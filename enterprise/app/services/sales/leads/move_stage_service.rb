class Sales::Leads::MoveStageService
  # SSOT §21.2: "Agendado só pode existir por reunião real. Arrastar manualmente um card para
  # Agendado sem evento de Calendar deve ser bloqueado." O mesmo raciocínio vale pra Ganho/Perdido
  # (§17.4): são fatos que só podem nascer de uma ação real de negócio (Calendar confirmado;
  # resultado comercial registrado), nunca de um drag solto que não passou pelo serviço que
  # valida e grava o resto do estado junto (ganho_em, motivo_perda, relacao_atual...).
  #
  # `user` é o mesmo parâmetro que já distingue as duas origens possíveis desta chamada: o
  # controller (Sales::LeadsController#move) sempre passa `user: Current.user`, presente porque é
  # uma ação humana via API; a sincronização do Operational Engine (OperationalEngine::
  # SalesProjectionSync/ComercialProjectionSync) passa `user: nil`, porque é o sistema refletindo
  # um fato já gravado no Supabase. Não criamos uma flag nova pra isso -- reaproveitamos a
  # fronteira de confiança que já existe.
  PROTECTED_STAGE_KEYS = %w[agendado ganho perdido].freeze

  class ProtectedTransitionError < StandardError; end

  def initialize(lead:, stage:, position: nil, user: nil)
    @lead = lead
    @stage = stage
    @position = position
    @user = user
  end

  def perform
    raise ArgumentError, 'stage must belong to the lead pipeline' if @stage.sales_pipeline_id != @lead.sales_pipeline_id
    raise ProtectedTransitionError, "#{@stage.engine_stage_key} só pode ser definido por uma ação real de negócio" if blocked_manual_transition?
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

  def blocked_manual_transition?
    @user.present? && @stage.id != @lead.sales_stage_id && PROTECTED_STAGE_KEYS.include?(@stage.engine_stage_key)
  end

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
