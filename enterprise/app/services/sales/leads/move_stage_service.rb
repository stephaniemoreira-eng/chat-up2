class Sales::Leads::MoveStageService
  # SSOT §21.2: "Agendado só pode existir por reunião real. Arrastar manualmente um card para
  # Agendado sem evento de Calendar deve ser bloqueado." O mesmo raciocínio vale pra Ganho/Perdido
  # (§17.4): são fatos que só podem nascer de uma ação real de negócio (Calendar confirmado;
  # resultado comercial registrado), nunca de um drag solto que não passou pelo serviço que
  # valida e grava o resto do estado junto (ganho_em, motivo_perda, relacao_atual...).
  #
  # `user` identifica a ação humana no controller. A única exceção é a projeção do Operational
  # Engine, que precisa declarar `system_source: :operational_engine`; `user: nil` por si só não
  # é uma autorização para fabricar uma etapa protegida.
  PROTECTED_STAGE_KEYS = Sales::Stage::PROTECTED_ENGINE_STAGE_KEYS

  class ProtectedTransitionError < StandardError; end
  class EngineManagedLeadError < ProtectedTransitionError; end

  # Exposto como class method (não só a lógica privada de instância) porque um card recém-criado
  # já direto numa stage won/lost (ex.: ComercialProjectionSync#create, um lead que chega no
  # Engine já como 'ganho') nunca passa por #perform -- não existe "mover" um card que ainda não
  # tinha stage nenhuma -- mas ainda precisa do mesmo status/closed_at corretos desde o início.
  def self.status_for(stage)
    return 'won' if stage.won?
    return 'lost' if stage.lost?

    'open'
  end

  def initialize(lead:, stage:, position: nil, user: nil, system_source: nil)
    @lead = lead
    @stage = stage
    @position = position
    @user = user
    @system_source = system_source
  end

  def perform
    raise ArgumentError, 'stage must belong to the lead pipeline' if @stage.sales_pipeline_id != @lead.sales_pipeline_id
    raise ProtectedTransitionError, blocked_transition_message if blocked_manual_transition?
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
    return true if @stage.id != @lead.sales_stage_id && @lead.pipeline.engine_kind.present? && @system_source != :operational_engine

    @stage.id != @lead.sales_stage_id &&
      PROTECTED_STAGE_KEYS.include?(@stage.engine_stage_key) &&
      @system_source != :operational_engine
  end

  def blocked_transition_message
    return 'pipeline is managed by the Operational Engine' if @lead.pipeline.engine_kind.present? && @system_source != :operational_engine

    "#{@stage.engine_stage_key} só pode ser definido por uma ação real de negócio"
  end

  def move_lead
    @lead.update!(
      stage: @stage,
      position: @position || next_position,
      stage_changed_at: Time.current,
      status: self.class.status_for(@stage),
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
