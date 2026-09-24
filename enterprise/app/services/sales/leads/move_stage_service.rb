class Sales::Leads::MoveStageService
  # SSOT §21.2: "Agendado só pode existir por reunião real. Arrastar manualmente um card para
  # Agendado sem evento de Calendar deve ser bloqueado." O mesmo raciocínio vale pra Ganho/Perdido
  # (§17.4): são fatos que só podem nascer de uma ação real de negócio (Calendar confirmado;
  # resultado comercial registrado), nunca de um drag solto que não passou pelo serviço que
  # valida e grava o resto do estado junto (ganho_em, motivo_perda, relacao_atual...).
  #
  # `system_source: :operational_engine` é o único sinal que autoriza mover pra uma stage
  # protegida -- não a ausência de `user`. `user: nil` sozinho não prova origem de sistema: é
  # verdade também num script de console ou num caller futuro que só esqueça de passar `user:`.
  # A fronteira de confiança tem que ser uma declaração explícita de quem chama (só
  # OperationalEngine::SalesProjectionSync/ComercialProjectionSync a faz), não a ausência de um
  # argumento.
  #
  # CP-05 (P1-023-03; SSOT §4, §21.2, §30, §28.39): num card GERIDO pelo Engine (tem
  # `operational_lead_id` -- só as projeções o gravam) a etapa é reflexo do Supabase, então
  # QUALQUER mudança de coluna sem `system_source: :operational_engine` é recusada, não só a
  # entrada em Agendado/Ganho/Perdido -- inclusive sair de Agendado (a reunião real continua tendo
  # existido, §28.29). O drag humano permitido no Kanban Comercial não chega aqui: o controller o
  # converte em ação do Engine (OperationalEngine::AdvanceEtapaComercialService), que persiste a
  # etapa + evento e só então projeta. Cards nativos (sem vínculo) mantêm o comportamento próprio.
  PROTECTED_STAGE_KEYS = %w[agendado ganho perdido].freeze

  class ProtectedTransitionError < StandardError; end

  ENGINE_MANAGED_MESSAGE = 'card gerido pelo Operational Engine: a etapa só muda por uma ação do Engine'.freeze

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
    raise ProtectedTransitionError, ENGINE_MANAGED_MESSAGE if blocked_engine_managed_move?
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

  def blocked_engine_managed_move?
    @stage.id != @lead.sales_stage_id && @lead.operational_lead_id.present? && @system_source != :operational_engine
  end

  def blocked_manual_transition?
    @stage.id != @lead.sales_stage_id &&
      PROTECTED_STAGE_KEYS.include?(@stage.engine_stage_key) &&
      @system_source != :operational_engine
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
