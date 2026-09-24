class Api::V1::Accounts::Sales::LeadsController < Api::V1::Accounts::Sales::BaseController
  before_action -> { check_authorization(Sales::Lead) }
  before_action :set_lead, only: [
    :show, :update, :destroy, :move, :link_conversation, :unlink_conversation, :timeline, :update_summary,
    :register_callback_realizado, :register_no_show, :set_propensao, :register_resultado_comercial,
    :advance_etapa_comercial, :remove_no_show, :assumir, :devolver
  ]
  before_action :set_operational_lead, only: [
    :register_callback_realizado, :register_no_show, :set_propensao, :register_resultado_comercial,
    :advance_etapa_comercial, :remove_no_show, :assumir, :devolver
  ]
  # CP-05 (P1-025-02, §21.3): ações Comerciais só pelo card do pipeline Comercial -- um card
  # Prospect vinculado ao mesmo lead não serve de atalho. As guardas de domínio de verdade ficam no
  # Engine (OperationalEngine::ComercialActionGuard); esta é só a fronteira da UI.
  before_action :ensure_comercial_card, only: [
    :register_callback_realizado, :register_no_show, :set_propensao, :register_resultado_comercial,
    :advance_etapa_comercial, :remove_no_show
  ]

  rescue_from Sales::Leads::MoveStageService::ProtectedTransitionError, with: :render_protected_transition_error
  rescue_from OperationalEngine::RegisterCallbackRealizadoService::InvalidTransitionError, with: :render_action_error
  rescue_from OperationalEngine::RegisterResultadoComercialService::AlreadyResolvedError, with: :render_action_error
  rescue_from OperationalEngine::RegisterResultadoComercialService::InvalidResultadoError, with: :render_action_error
  rescue_from OperationalEngine::ComercialActionGuard::InvalidContextError, with: :render_action_error
  rescue_from OperationalEngine::SetPropensaoService::InvalidPropensaoError, with: :render_action_error
  rescue_from OperationalEngine::DevolucaoSync::SyncError, with: :render_action_error

  def index
    @leads = filtered_leads.ordered
  end

  # Indicadores do Dashboard (Up Sales). Ver docs/fork/ADR-0004-up-sales-reskin.md.
  def summary
    leads = Current.account.sales_leads

    render json: {
      leads_count: leads.count,
      deals_won_count: leads.won.count,
      last_search_at: leads.where(source: 'busca_prospeccao').maximum(:created_at)
    }
  end

  def show; end

  def create
    @lead = Sales::Leads::CreateService.new(account: Current.account, params: lead_params).perform
  end

  def update
    @lead.update!(lead_update_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  # CP-05 (P1-023-03, §21.2): num card Comercial gerido pelo Engine o drag vira a ação
  # Engine-controlled de movimentação Comercial (o Engine valida, persiste etapa + evento e só então
  # projeta); qualquer outro card gerido pelo Engine é recusado pelo MoveStageService. Cards nativos
  # seguem o fluxo de sempre.
  def move
    stage = @lead.pipeline.stages.find(params.require(:sales_stage_id))
    return move_via_engine(stage) if @lead.operational_lead_id.present? && comercial_card?

    @lead = Sales::Leads::MoveStageService.new(lead: @lead, stage: stage, position: params[:position], user: Current.user).perform
  end

  def link_conversation
    conversation = Current.account.conversations.find(params.require(:conversation_id))
    Sales::Leads::LinkConversationService.new(lead: @lead, conversation: conversation).perform
  end

  def unlink_conversation
    @lead.lead_conversations.find_by!(conversation_id: params.require(:conversation_id)).destroy!
    head :ok
  end

  def timeline
    @timeline = Sales::Leads::TimelineBuilderService.new(
      lead: @lead,
      before: params[:before].present? ? Time.zone.at(params[:before].to_i) : nil,
      per_page: params[:per_page].presence || Sales::Leads::TimelineBuilderService::DEFAULT_PER_PAGE
    ).perform
  end

  def update_summary
    @lead = Sales::Leads::UpdateSummaryService.new(lead: @lead, summary: params.require(:summary), user: Current.user).perform
  end

  # Fase 9 (§16.3, §21.2): ações humanas mínimas do Kanban Comercial. Todas passam pelo Engine
  # (nunca escrevem em Sales::Lead diretamente, §5.7) -- o `@lead` acima de re-sincronizado no
  # retorno é só a projeção já atualizada pelo próprio serviço.
  def register_callback_realizado
    OperationalEngine::RegisterCallbackRealizadoService.call!(lead: @operational_lead, user_id: Current.user.id)
    @lead.reload
  end

  def register_no_show
    OperationalEngine::RegisterNoShowService.call!(lead: @operational_lead, user_id: Current.user.id)
    @lead.reload
  end

  def set_propensao
    OperationalEngine::SetPropensaoService.call!(
      lead: @operational_lead, propensao: params.require(:propensao_fechamento), user_id: Current.user.id
    )
    @lead.reload
  end

  def register_resultado_comercial
    OperationalEngine::RegisterResultadoComercialService.call!(
      lead: @operational_lead, resultado: params.require(:resultado_comercial),
      motivo_perda: params[:motivo_perda], user_id: Current.user.id
    )
    @lead.reload
  end

  # CP-05 (P1-023-03, §8.4, §21.2): movimentação Comercial permitida como ação do Engine (botão).
  def advance_etapa_comercial
    OperationalEngine::AdvanceEtapaComercialService.call!(
      lead: @operational_lead, etapa: params.require(:etapa_comercial), user_id: Current.user.id
    )
    @lead.reload
  end

  # CP-05 (P2-025-03, §20.3): remoção manual da tag NO-SHOW -- o evento reuniao_no_show permanece.
  def remove_no_show
    OperationalEngine::RemoveNoShowTagService.call!(lead: @operational_lead, user_id: Current.user.id)
    @lead.reload
  end

  # Fase 3 (§18.2/§18.3, §21.2): Assumir/Devolver. O serviço já é idempotente e trava por linha
  # (OperationalEngine::TakeoverService) -- só faltava o caminho de UI até aqui.
  def assumir
    OperationalEngine::TakeoverService.assumir!(lead: @operational_lead, user_id: Current.user.id)
    @lead.reload
  end

  # CP-06 (P1-026-01): a devolução sincroniza antes de reativar a Lavínia; se a sincronização
  # falhar, o lead continua humano e o operador recebe 422 com o motivo (pode repetir).
  def devolver
    OperationalEngine::TakeoverService.devolver!(lead: @operational_lead, user_id: Current.user.id)
    @lead.reload
  end

  private

  def move_via_engine(stage)
    operational_lead = OperationalEngine::Lead.find_by(lead_id: @lead.operational_lead_id)
    return render json: { error: 'lead do Operational Engine não encontrado' }, status: :not_found unless operational_lead

    OperationalEngine::AdvanceEtapaComercialService.call!(lead: operational_lead, etapa: stage.engine_stage_key, user_id: Current.user.id)
    @lead.reload
  end

  def comercial_card?
    @lead.pipeline.engine_kind == Sales::Pipelines::SeedComercialPipelineService::ENGINE_KIND
  end

  def ensure_comercial_card
    return if comercial_card?

    render json: { error: 'ação Comercial só pode ser feita pelo card do pipeline Comercial' }, status: :unprocessable_entity
  end

  def set_operational_lead
    unless @lead.operational_lead_id
      return render json: { error: 'este negócio não está vinculado a um lead do Operational Engine' }, status: :unprocessable_entity
    end

    @operational_lead = OperationalEngine::Lead.find_by(lead_id: @lead.operational_lead_id)
    render json: { error: 'lead do Operational Engine não encontrado' }, status: :not_found unless @operational_lead
  end

  def render_action_error(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def render_protected_transition_error(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def filtered_leads
    leads = Current.account.sales_leads.includes(:prospecting_result)
    leads = leads.where(sales_pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    leads = leads.where(sales_stage_id: params[:stage_id]) if params[:stage_id].present?
    leads = leads.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    leads = leads.joins(:lead_conversations).where(sales_lead_conversations: { conversation_id: params[:conversation_id] }) if params[:conversation_id].present?
    leads
  end

  def set_lead
    @lead = Current.account.sales_leads.find(params[:id])
  end

  def lead_params
    params.require(:lead).permit(:contact_id, :pipeline_id, :sales_stage_id, *shared_lead_attributes)
  end

  def lead_update_params
    params.require(:lead).permit(*shared_lead_attributes)
  end

  def shared_lead_attributes
    [:title, :source, :value, :probability, :expected_close_date, :assignee_id, :notes,
     { custom_attributes: {}, additional_attributes: {} }]
  end
end
