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
# PATCH/DELETE schedule_meeting (atualizar/cancelar) ficam de fora por enquanto: dependem de
# rotas equivalentes no up2-agents (S-9) que ainda não existem. Adicionar quando existirem.
post 'operational_engine/tools/schedule_meeting', to: 'operational_engine/tools#schedule_meeting'
post 'operational_engine/tools/register_callback', to: 'operational_engine/tools#register_callback'
get 'operational_engine/tools/availability', to: 'operational_engine/tools#availability'
