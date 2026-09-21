# S-4 parte 2 (plano do Marco 1): o "aplicador de ações" -- um endpoint por acao_sugerida
# operacional (SSOT §12.4), como docs/agent-runtime-v1.md (up2-agents) pede: "um endpoint por
# acao_sugerida operacional, respondendo ok/blocked/error". Chamado pelo ActionDispatcher do
# up2-agents SÓ depois que a saída do modelo já passou pela validação Zod do contrato -- nunca
# pelo modelo diretamente (nenhuma ferramenta de mutação é bindada em modo agent).
#
# Rota irmã, não duplicata, de Api::V1::Accounts::OperationalEngine::ToolsController#register_callback
# (S-5): aquela existe pra o modo prompt (a Lavínia chamando a tool do LangGraph diretamente);
# esta existe pra o modo agent (o Engine despachando depois da validação). As duas convergem no
# mesmo RegisterCallbackService de propósito -- é a mesma regra de negócio, dois chamadores.
#
# `::OperationalEngine::*`/`Concerns::*` com prefixo explícito: mesmo motivo do ToolsController
# (colisão de nome com o módulo de domínio raiz).
class Api::V1::Accounts::OperationalEngine::ActionsController < Api::V1::Accounts::BaseController
  include ::Concerns::OperationalEngine::ToolAuthentication

  def iniciar_orcamento
    render_tool_result ::OperationalEngine::Tools::StartBudgetService.new(
      account: Current.account, conversation_id: params[:conversation_id]
    ).call
  end

  def iniciar_agendamento
    render_tool_result ::OperationalEngine::Tools::StartSchedulingService.new(
      account: Current.account, conversation_id: params[:conversation_id]
    ).call
  end

  def registrar_callback
    render_tool_result ::OperationalEngine::Tools::RegisterCallbackService.new(
      account: Current.account, conversation_id: params[:conversation_id]
    ).call
  end

  def handoff_comercial
    render_tool_result ::OperationalEngine::Tools::HandoffToCommercialService.new(
      account: Current.account, conversation_id: params[:conversation_id], motivo_handoff: params[:motivo_handoff]
    ).call
  end

  def encerrar_sem_interesse
    render_tool_result ::OperationalEngine::Tools::CloseAsNotInterestedService.new(
      account: Current.account, conversation_id: params[:conversation_id]
    ).call
  end

  def encerrar_nao_qualificado
    render_tool_result ::OperationalEngine::Tools::CloseAsUnqualifiedService.new(
      account: Current.account, conversation_id: params[:conversation_id]
    ).call
  end

  def ativar_nao_contatar
    render_tool_result ::OperationalEngine::Tools::ActivateDoNotContactService.new(
      account: Current.account, conversation_id: params[:conversation_id]
    ).call
  end
end
