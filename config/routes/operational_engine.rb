# Fork-owned routes for the Operational Engine tool endpoints (S-5, plano do Marco 1).
#
# Drawn from config/routes.rb via `draw :operational_engine`, from inside the same
# `namespace :api -> namespace :v1 -> resources :accounts -> scope module: :accounts` nesting as
# `sales.rb` -- see the header comment there for why `path:`/raw routes are used instead of a
# wrapping `scope` block.
#
# Namespace separado de Sales:: de propósito: estas rotas não são chamadas por um usuário logado
# no navegador, são chamadas pelo runtime da Lavínia no up2-agents (servidor-a-servidor), com uma
# autenticação própria -- ver Api::V1::Accounts::OperationalEngine::ToolsController. Contrato B do
# plano do Marco 1: resposta sempre {"ok": true, ...} | {"ok": false, "reason": "..."}.
#
post 'operational_engine/tools/schedule_meeting', to: 'operational_engine/tools#schedule_meeting'
patch 'operational_engine/tools/schedule_meeting/:event_id', to: 'operational_engine/tools#update_meeting'
delete 'operational_engine/tools/schedule_meeting/:event_id', to: 'operational_engine/tools#cancel_meeting'
# CP-10 (P1-VAL-03): as mesmas ações sem :event_id -- é o caminho das ferramentas "Atualizar evento"/
# "Cancelar evento" da Lavínia no modo agent; o Engine resolve a reunião confirmada do próprio lead.
patch 'operational_engine/tools/schedule_meeting', to: 'operational_engine/tools#update_meeting'
delete 'operational_engine/tools/schedule_meeting', to: 'operational_engine/tools#cancel_meeting'
post 'operational_engine/tools/register_callback', to: 'operational_engine/tools#register_callback'
get 'operational_engine/tools/availability', to: 'operational_engine/tools#availability'

# S-4 parte 1: health + Snapshot (SSOT §12.3), pedidos por docs/agent-runtime-v1.md (up2-agents)
# para destravar o modo agent. Mesma autenticação servidor-a-servidor do Contrato B acima.
get 'operational_engine/health', to: 'operational_engine/snapshot#health'
get 'operational_engine/snapshot', to: 'operational_engine/snapshot#show'

# S-4 parte 2: um endpoint por acao_sugerida operacional (SSOT §12.4) -- o aplicador de ações
# despachado pelo ActionDispatcher do up2-agents depois que a saída do modelo já passou pela
# validação Zod. Nomes em português batendo 1:1 com o enum ACAO_SUGERIDA de lá, de propósito --
# não é o mesmo path de operational_engine/tools/* (Contrato B/modo prompt), mesmo quando convergem
# no mesmo service por baixo (registrar_callback).
post 'operational_engine/actions/iniciar_orcamento', to: 'operational_engine/actions#iniciar_orcamento'
post 'operational_engine/actions/iniciar_agendamento', to: 'operational_engine/actions#iniciar_agendamento'
post 'operational_engine/actions/registrar_callback', to: 'operational_engine/actions#registrar_callback'
post 'operational_engine/actions/handoff_comercial', to: 'operational_engine/actions#handoff_comercial'
post 'operational_engine/actions/encerrar_sem_interesse', to: 'operational_engine/actions#encerrar_sem_interesse'
post 'operational_engine/actions/encerrar_nao_qualificado', to: 'operational_engine/actions#encerrar_nao_qualificado'
post 'operational_engine/actions/ativar_nao_contatar', to: 'operational_engine/actions#ativar_nao_contatar'

# CP-03 (P1-021-02): commit da saída estruturada do turno (dados_extraidos, decisao_qualificacao,
# aguardando_resposta, ultimo_ponto, resumo_oportunidade) -- o up2-agents chama ANTES de despachar a
# acao_sugerida, com a mesma identidade de turno (turn_id).
post 'operational_engine/turno', to: 'operational_engine/actions#saida_estruturada'
