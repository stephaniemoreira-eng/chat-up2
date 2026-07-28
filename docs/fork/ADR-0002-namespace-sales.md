# ADR-0002 — Namespace do módulo comercial: `Sales::`, não `Crm::`

- **Status:** aceito
- **Data:** 2026-07-28

## Contexto

O produto é descrito como "CRM" e o vocabulário natural do time é CRM, lead, pipeline, kanban.
A escolha óbvia seria namespace `Crm::` com tabelas `crm_*`.

Ao inspecionar o upstream 4.16.0, três fatos desaconselham isso:

**1. O namespace `Crm::` já está ocupado no OSS**, com outro significado — integrações com CRMs
externos:

```
app/services/crm/base_processor_service.rb        → Crm::BaseProcessorService
app/services/crm/leadsquared/processor_service.rb → Crm::Leadsquared::ProcessorService
```
mais a feature flag `crm_integration` (`config/integration/apps.yml`).

**2. O upstream já começou a construir o próprio CRM.** Existe a flag `crm_v2`
(`chatwoot_internal: true`, desligada) já consumida em quatro lugares:

```
app/services/search_service.rb:173
app/services/contacts/filter_service.rb:33
app/controllers/api/v1/accounts/contacts_controller.rb:123
app/jobs/account/contacts_export_job.rb:64
```

todos via `Contact.resolved_contacts(use_crm_v2:)`.

**3. `Contact` já tem o conceito de lead:** `enum contact_type: { visitor: 0, lead: 1, customer: 2 }`.

Ou seja: "CRM" é vocabulário que o upstream está ativamente reivindicando, num trabalho em voo
cujo escopo final não conhecemos. Batizar nosso módulo `Crm::` colidiria em nome de módulo, nome
de flag e significado — e o custo de renomear depois de dez fases implementadas é proibitivo.

## Decisão

Namespace **`Sales::`**, tabelas **`sales_*`**, flags **`sales_pipeline`** e **`sales_kanban`**.

```
Sales::Pipeline  Sales::Stage  Sales::Lead  Sales::LeadConversation
Sales::StageTransition  Sales::Task  Sales::Activity

sales_pipelines  sales_stages  sales_leads  sales_lead_conversations
sales_stage_transitions  sales_tasks  sales_activities
```

Segue o precedente do próprio upstream: `Captain::Assistant` → tabela `captain_assistants`.

### Separação deliberada entre namespace de código e rótulo de produto

**No código** é `Sales::`. **Para o usuário** é "CRM":

- URL: `/app/accounts/:id/crm`
- Rotas de API: `/api/v1/accounts/:id/crm/...` — em `config/routes/sales.rb`, o segmento `crm` é
  passado como `path:` diretamente em cada `resources` (ex. `resources :pipelines, module: :sales,
  path: 'crm/pipelines'`), **não** via um `scope :crm do ... end` envolvente. Isso não é estético:
  como as rotas já estão aninhadas dentro de `resources :accounts do ... end` (o próprio Rails
  insere `accounts/:account_id`), um `scope` com path envolvendo o `resources` insere seu segmento
  **antes** desse prefixo, gerando `/api/v1/crm/accounts/:account_id/pipelines` em vez de
  `/api/v1/accounts/:account_id/crm/pipelines` — verificado empiricamente. `path:` direto no
  `resources` não tem esse problema e `module: :sales` se propaga automaticamente para
  `resources` aninhados no mesmo bloco, sem precisar repetir.
- i18n: arquivo `sales.json`, namespace de chaves `SALES`, **textos dizendo "CRM"**
- Item de sidebar: rótulo "CRM"

O usuário nunca vê a palavra "Sales". Ganhamos imunidade a colisão sem perder o vocabulário do
produto.

## Regra derivada (importante)

Não usar `Contact#contact_type` nem `Contact.resolved_contacts` na lógica do módulo comercial.
Esse é exatamente o caminho que o `crm_v2` do upstream vai reescrever. `Sales::Lead` é uma entidade
própria com `belongs_to :contact`; a qualificação comercial vive em `sales_leads.status` e
`sales_leads.stage_id`, não em `contacts.contact_type`.

## Consequências

**Positivas:** zero colisão de constante, de tabela, de flag e de rota com o upstream, hoje e
depois que o `crm_v2` for lançado. Elimina a ambiguidade de `Crm::` ter dois significados no mesmo
repositório.

**Negativas:** há uma tradução mental entre código (`Sales::`) e produto ("CRM") que precisa ser
conhecida por quem entra no projeto — motivo deste ADR. Um `grep crm` encontra tanto as
integrações externas do upstream quanto nossas rotas; preferir `grep -r "Sales::"` ou `sales_`
para o nosso domínio.

**A monitorar a cada merge do upstream:** o estado da flag `crm_v2`. Se o upstream lançar um CRM
completo, a decisão de convergir com ele ou seguir divergindo é de produto, não de código — e
este ADR deve ser revisitado, não silenciosamente contrariado.
