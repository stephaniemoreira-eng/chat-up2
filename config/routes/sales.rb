# Fork-owned API routes for the commercial (CRM) module.
#
# Drawn from config/routes.rb via `draw :sales`, from inside:
#   namespace :api -> namespace :v1 -> resources :accounts -> scope module: :accounts
# so every route below is already nested under /api/v1/accounts/:account_id/.
#
# `path: 'crm/pipelines'` is set directly on the `resources` call rather than via a wrapping
# `scope :crm do ... end` block: because we're already inside `resources :accounts do ... end`
# (Rails' own account_id nesting), a wrapping `scope` here places its path segment BEFORE the
# `accounts/:account_id` prefix Rails inserts for nested resources, producing the wrong URL
# (verified empirically: `scope :crm do resources :pipelines end end` yields
# `/api/v1/crm/accounts/:account_id/pipelines`, not `/api/v1/accounts/:account_id/crm/pipelines`).
# A `path:` option passed directly to `resources` does not have this problem.
#
# `module: :sales` resolves controllers to Api::V1::Accounts::Sales::* and propagates to the
# nested `resources :stages` block without needing to repeat it.
#
# Naming: code is namespaced `Sales::`/`sales_*`, but the URL segment says "crm" — upstream is
# actively claiming the `Crm::` namespace and the `crm_v2` feature flag.
# See docs/fork/ADR-0002-namespace-sales.md.
resources :pipelines, module: :sales, path: 'crm/pipelines' do
  post :reorder, on: :collection

  resources :stages, only: [:index, :show, :create, :update, :destroy] do
    post :reorder, on: :collection
  end
end

resources :leads, module: :sales, path: 'crm/leads' do
  member do
    post :move
    post :link_conversation
    delete :unlink_conversation
    get :timeline
    patch :update_summary
  end
  collection do
    get :summary
  end
end

post 'crm/prospecting/search', to: 'sales/prospecting#search'
post 'crm/prospecting/create_leads', to: 'sales/prospecting#create_leads'

resource :follow_up, module: :sales, path: 'crm/follow_up', controller: 'follow_up', only: [:show, :update] do
  post :sync, on: :collection
end

# Não é uma rota do módulo Sales:: (CRM) -- fica neste arquivo só para não abrir um segundo
# `draw` em config/routes.rb (ver ADR-0001). Ver docs/fork/ADR-0004-up-sales-reskin.md.
get 'up_sales/calendar_events', to: 'up_sales/calendar_events#index'
post 'up_sales/calendar_events', to: 'up_sales/calendar_events#create'
