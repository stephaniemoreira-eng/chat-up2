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

  # CP-03 (P1-021-01): toda ação é idempotente pela identidade estável do turno (`turn_id`) --
  # replay do mesmo turno devolve o resultado guardado sem reaplicar a mutação; turno novo na mesma
  # conversa roda normalmente. Ver OperationalEngine::TurnIdempotency.

  def iniciar_orcamento
    render_tool_result(turn_idempotent('acao:iniciar_orcamento') do
      ::OperationalEngine::Tools::StartBudgetService.new(
        account: Current.account, conversation_id: params[:conversation_id]
      ).call
    end)
  end

  def iniciar_agendamento
    render_tool_result(turn_idempotent('acao:iniciar_agendamento') do
      ::OperationalEngine::Tools::StartSchedulingService.new(
        account: Current.account, conversation_id: params[:conversation_id]
      ).call
    end)
  end

  def registrar_callback
    render_tool_result(turn_idempotent('acao:registrar_callback') do
      ::OperationalEngine::Tools::RegisterCallbackService.new(
        account: Current.account, conversation_id: params[:conversation_id]
      ).call
    end)
  end

  def handoff_comercial
    render_tool_result(turn_idempotent('acao:handoff_comercial') do
      ::OperationalEngine::Tools::HandoffToCommercialService.new(
        account: Current.account, conversation_id: params[:conversation_id], motivo_handoff: params[:motivo_handoff]
      ).call
    end)
  end

  def encerrar_sem_interesse
    render_tool_result(turn_idempotent('acao:encerrar_sem_interesse') do
      ::OperationalEngine::Tools::CloseAsNotInterestedService.new(
        account: Current.account, conversation_id: params[:conversation_id]
      ).call
    end)
  end

  def encerrar_nao_qualificado
    render_tool_result(turn_idempotent('acao:encerrar_nao_qualificado') do
      ::OperationalEngine::Tools::CloseAsUnqualifiedService.new(
        account: Current.account, conversation_id: params[:conversation_id]
      ).call
    end)
  end

  def ativar_nao_contatar
    render_tool_result(turn_idempotent('acao:ativar_nao_contatar') do
      ::OperationalEngine::Tools::ActivateDoNotContactService.new(
        account: Current.account, conversation_id: params[:conversation_id]
      ).call
    end)
  end

  # CP-03 (P1-021-02): a parte semântica do turno. `saida` chega crua (hash aninhado de
  # dados_extraidos) de propósito -- quem valida e faz a whitelist é o ApplyStructuredOutputService;
  # a chamada já passou pela autenticação servidor-a-servidor do Engine.
  #
  # CP-16B (P2-VAL-20): `modo=ressincronizacao` é o commit do turno silencioso pós-devolução
  # (OperationalEngine::DevolucaoResync) -- só fatos de continuidade, nenhuma decisão/ação.
  def saida_estruturada
    saida = params[:saida].respond_to?(:to_unsafe_h) ? params[:saida].to_unsafe_h : {}
    render_tool_result(turn_idempotent('saida_estruturada') do
      ::OperationalEngine::ApplyStructuredOutputService.new(
        account: Current.account, conversation_id: params[:conversation_id], saida: saida,
        ressincronizacao: params[:modo] == 'ressincronizacao'
      ).call
    end)
  end

  private

  def turn_idempotent(operacao, &)
    ::OperationalEngine::TurnIdempotency.call(conta_id: Current.account.id, operacao: operacao, turn_id: params[:turn_id], &)
  end
end
