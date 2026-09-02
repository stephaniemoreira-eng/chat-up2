# ADR-0001 — Estratégia de extensão do fork

- **Status:** aceito (seção 4 revisada em 2026-07-28, mesmo dia, após correção da branch-base)
- **Data:** 2026-07-28
- **Contexto do fork:** este repositório (`chat-up2`) é uma segunda camada de fork —
  `chatwoot/chatwoot` → `fazer-ai/chatwoot` (base real de trabalho, branch `fazer-ai-main` /
  `fix/agent-bots-current-account-order`) → `chat-up2` (este). Não é fork direto do Chatwoot OSS;
  a base correta carrega centenas de commits próprios da fazer.ai (WhatsApp Baileys/Z-API,
  assinatura por inbox, chat interno, mensagens agendadas, branding customizado, etc.), com seu
  próprio processo de sync documentado em `.claude/skills/sync-fork/SKILL.md` no repositório da
  fazer.ai. Este ADR foi escrito originalmente contra o Chatwoot OSS puro (branch errada); a
  seção 4 foi corrigida no mesmo dia ao descobrir que a fazer.ai já resolveu o mesmo problema de
  outra forma, documentada naquele skill.

## Contexto

Este repositório é um fork do Chatwoot que precisa acrescentar um módulo comercial completo
(Leads, Pipelines, Kanban, Timeline, Tarefas, Automações, IA, Dashboard) **sem perder a
capacidade de fazer merge das versões futuras do upstream**.

O conflito de merge não é um incômodo estético: cada arquivo nativo que editamos é um arquivo
que vamos reconciliar manualmente a cada release do upstream, para sempre. O custo é recorrente
e cresce com o tempo. Portanto o desenho precisa minimizar deliberadamente a superfície de contato.

## Decisão

### 1. Código novo vive em diretórios novos

O Chatwoot já carrega um overlay Enterprise, configurado em `config/application.rb`:

```ruby
config.eager_load_paths += Dir["#{Rails.root}/enterprise/app/**"]
config.eager_load_paths << Rails.root.join('enterprise/lib')
config.paths['app/views'].unshift('enterprise/app/views')
```

Todo o backend do módulo comercial vive sob `enterprise/app/**` e `enterprise/lib/**`, em
subdiretórios próprios (`sales/`), que o upstream nunca cria. Frontend vive em
`app/javascript/dashboard/{routes/dashboard/sales,components-next/Sales,api/sales,stores/sales}/`.

Consequência: models, services, controllers, policies, jobs, listeners, views jbuilder,
componentes Vue, stores e API clients são **100% arquivos novos, com zero conflito de merge**.

### 2. Comportamento em models nativos entra por `include_mod_with`, não por edição

`config/initializers/01_inject_enterprise_edition_module.rb` (portado do GitLab) injeta
`prepend_mod_with` / `include_mod_with` / `extend_mod_with` em `Module`. Cada model nativo já
termina com os ganchos:

```ruby
Conversation.include_mod_with('Concerns::Conversation')
Conversation.prepend_mod_with('Conversation')
```

Para dar a `Account`, `Contact` e `Conversation` as associações do módulo comercial, editamos
`enterprise/app/models/enterprise/concerns/{account,contact,conversation}.rb` — arquivos do
overlay, não `app/models/*.rb`. O mesmo vale para `Enterprise::ActionService` (ações de
automação) e `Enterprise::AutomationRule` (condições/ações disponíveis).

### 3. Rotas do fork ficam num arquivo próprio

`config/routes.rb` recebe **uma única linha** (`draw :sales`) dentro de
`scope module: :accounts`. Todas as nossas rotas vivem em `config/routes/sales.rb`.

Sem isso, cada fase do roadmap acrescentaria rotas a um arquivo de 745 linhas que o upstream
edita constantemente.

### 4. Feature flags do fork vivem em `settings` jsonb, não em coluna de bitset

`app/models/concerns/featurable.rb` usa FlagShihTzu sobre colunas `bigint`, e as posições de bit
vêm **da ordem de aparição em `config/features.yml`**. O cabeçalho desse arquivo é explícito:
`feature_flags` está cheia (63/63) e novas flags devem ir para `feature_flags_ext_1`.

**Histórico da decisão (revisado no mesmo dia em que foi tomada):** a primeira versão deste ADR
optou por uma coluna de bitset própria (`feature_flags_custom_1`), isolada da `feature_flags_ext_1`
que o upstream usa. Tecnicamente funcionava — nunca colidiria com o upstream, por construção.

Ao descobrir a branch-base correta deste trabalho (`fazer-ai/chatwoot`, não o Chatwoot OSS puro),
encontrei em `.claude/skills/sync-fork/SKILL.md` (documento interno da fazer.ai, que mantém esse
fork) que **eles já passaram exatamente por este problema** — o fork Pro deles (privado) precisou
acrescentar flags próprias (`kanban`, `internal_chat_pro`) e a primeira tentativa foi idêntica à
minha: coluna de bitset dedicada. Documentaram por que abandonaram essa abordagem: bitset —
mesmo em coluna própria — ainda exige gerenciar posição de bit, ainda pode estourar o limite de 63
por coluna, e ainda exige migração de dados se um dia precisar mudar de coluna de novo. A solução
que shipped: mover as flags do fork para o **`settings` jsonb** (coluna que já existe nativamente
em `accounts`), via `store_accessor`, com `feature_enabled?`/`enable_features`/`disable_features`
sobrescritos para rotear esses nomes específicos através de `settings` — deixando
`config/features.yml` **intocado, byte-idêntico ao upstream, para sempre**.

Adotei a mesma solução, já validada em produção por quem mantém a base deste fork, em vez de
reinventar uma variante pior do mesmo problema:

```ruby
# enterprise/app/models/enterprise/concerns/account.rb
FORK_SETTINGS_FEATURES = %w[sales_pipeline sales_kanban].freeze

included do
  store_accessor :settings, :sales_pipeline_enabled, :sales_kanban_enabled
end

def feature_enabled?(name)
  return !!ActiveModel::Type::Boolean.new.cast(public_send("#{name}_enabled")) if FORK_SETTINGS_FEATURES.include?(name.to_s)

  super
end

def enable_features(*names)
  settings_names, bitmask_names = names.map(&:to_s).partition { |name| FORK_SETTINGS_FEATURES.include?(name) }
  settings_names.each { |name| public_send("#{name}_enabled=", true) }
  super(*bitmask_names)
end
# disable_features análogo
```

`config/features.yml` não recebe nenhuma entrada nova — nem mesmo um comentário. Motivo: um
comentário ali reintroduziria exatamente o problema que essa estratégia elimina (um touch
permanente e desnecessário num arquivo que deveria nunca precisar de reconciliação em merge).
A explicação vive só aqui e no `Enterprise::Concerns::Account`.

Nada mais no fluxo de feature flags muda: `account.enable_features!('sales_pipeline')`,
`account.feature_enabled?('sales_pipeline')` continuam funcionando exatamente como para qualquer
flag nativa — a store diferente é um detalhe de implementação invisível para quem chama.

### 5. Edições em arquivos nativos formam uma lista fechada e auditável

| Arquivo | Edição |
|---|---|
| `config/routes.rb` | 1 linha (`draw :sales`) + resources `up_sales_agent_config(s)` dentro de `namespace :super_admin` (ADR-0004, Super Admin de agente) |
| `config/features.yml` | **nenhuma** — permanece byte-idêntico ao upstream (seção 4) |
| `app/models/concerns/featurable.rb` | **nenhuma** |
| `db/schema.rb` | regenerado (nunca editado à mão) |
| `enterprise/app/models/enterprise/concerns/{account,contact,conversation}.rb` | append de associações + `FORK_SETTINGS_FEATURES`/`store_accessor` (feature flags: `sales_pipeline`, `sales_kanban`, `sales_scan`) |
| `enterprise/app/models/enterprise/automation_rule.rb` | append em duas listas |
| `enterprise/app/dispatchers/enterprise/async_dispatcher.rb` | append de listener |
| `lib/events/types.rb` | append de constantes |
| `lib/filters/filter_keys.yml` | append de um bloco |
| `app/javascript/dashboard/featureFlags.js` | bloco demarcado |
| `app/javascript/dashboard/i18n/locale/en/index.js` | 1 import + 1 spread |
| `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | 1 import + 1 spread |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | 1 bloco demarcado (marca dinâmica) + remoção de 3 itens do submenu "Conversas" (Menções/Participantes/Pastas, ADR-0004, reskin) |
| `app/javascript/dashboard/composables/useUISettings.js` | 1 entrada |
| `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` | 1 branch |
| `app/javascript/dashboard/components/ChatList.vue` | 2 valores default (`STATUS_TYPE.OPEN` → `ALL`, ADR-0004, reskin de Conversas) |
| `app/javascript/dashboard/store/modules/conversations/index.js` | 1 valor default (`chatStatusFilter`, mesmo motivo acima) |
| `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue` | classes de borda esquerda (cor de marca no item ativo, ADR-0004) |
| `app/javascript/dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue` | 1 classe de cor (`n-teal-9` → `n-brand`, ADR-0004) |
| `app/views/super_admin/application/_navigation.html.erb` | 1 bloco demarcado (link "Up Sales — Agentes", ADR-0004) |
| `config/schedule.yml` | append de 1 entrada (`sales_follow_up_sync_job`, ADR-0004, Follow-up) |
| `config/installation_config.yml` | append de blocos demarcados (`GOOGLE_PLACES_API_KEY`; `PAGESPEED_API_KEY`/`SCANNER_URL`/`SCANNER_TOKEN`, SCAN v1) |
| `app/controllers/super_admin/app_configs_controller.rb` | append na array `'google'` do mapping `allowed_configs` (mesmas chaves acima) |
| `app/helpers/super_admin/account_features_helper.rb` | `feature_display_names` faz merge com `Enterprise::Concerns::Account::FORK_SETTINGS_FEATURE_DISPLAY_NAMES` (rotulo amigavel pras flags fork-owned na tela de Features da conta) |

Regra operacional: **um conflito de merge fora desta lista significa que uma fase vazou
acoplamento.** Corrigir antes de seguir, em vez de aceitar o conflito. Ver
`UPSTREAM_MERGE_PLAYBOOK.md`.

## Alternativas consideradas

### Overlay `custom/` (rejeitada por ora, mantida como saída)

`ChatwootApp.extensions` suporta um terceiro overlay, ativado apenas pela existência de um
diretório `custom/` na raiz:

```ruby
def self.extensions
  if custom?        then %w[enterprise custom]
  elsif enterprise? then %w[enterprise]
  else %w[] end
end
```

É o slot oficialmente sancionado para forks e está vazio. Com ele, um
`custom/app/models/custom/automation_rule.rb` seria injetado pelos `prepend_mod_with` que já
existem — **sem editar nenhum arquivo do upstream**, nem mesmo os do overlay `enterprise/`.

Custo de habilitar: ~4 linhas em `config/application.rb` espelhando os load paths que hoje só
cobrem `enterprise/`.

Rejeitada nesta rodada por decisão de projeto (acoplamento moderado, seguir o padrão `Company`
que o upstream usa hoje). Fica registrada como **saída caso a dor de merge cresça**: a migração
de `enterprise/app/models/enterprise/*.rb` para `custom/app/models/custom/*.rb` é mecânica,
porque os dois overlays usam exatamente o mesmo mecanismo de injeção.

### Editar arquivos nativos livremente (rejeitada)

Mais rápido no curto prazo, custo crescente e permanente a cada versão do upstream.
Incompatível com o objetivo declarado de manter compatibilidade.

## Consequências

**Positivas:** merges do upstream ficam previsíveis; o módulo é removível desligando uma flag;
o código novo é testável em isolamento; a lista fechada da seção 5 é um contrato verificável
automaticamente (`git merge --no-commit` + inspeção).

**Negativas:** duas edições ficam em hotspots reais (`Sidebar.vue`, `ContactPanel.vue`), que o
upstream mexe com frequência — mitigado mantendo cada edição num bloco contíguo comentado, com o
conteúdo real extraído para componentes próprios. E `db/schema.rb` vai conflitar em todo merge,
por construção; a resolução é sempre regenerar, nunca editar.

## Referências

- `docs/fork/ADR-0002-namespace-sales.md`
- `docs/fork/ADR-0003-lead-domain-model.md`
- `docs/fork/UPSTREAM_MERGE_PLAYBOOK.md`
