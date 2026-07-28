# Playbook — merge do upstream deste fork

Procedimento para incorporar novas versões do fork-base neste repositório (`chat-up2`).

## Este é um fork de dois níveis — não confundir o "upstream" certo

```
chatwoot/chatwoot  →  fazer-ai/chatwoot  →  chat-up2 (este repositório)
   (Chatwoot OSS)       (base real de trabalho,       (nosso módulo comercial)
                         branch fazer-ai-main /
                         fix/agent-bots-current-account-order)
```

- **upstream imediato deste repositório é `fazer-ai/chatwoot`**, não `chatwoot/chatwoot`. Toda
  a lógica deste playbook (arquivos que conflitam, como resolver) é sobre sincronizar `chat-up2`
  com `fazer-ai/chatwoot`.
- A fazer.ai já mantém seu **próprio** processo, maduro e documentado, para sincronizar
  `fazer-ai/chatwoot` com `chatwoot/chatwoot` (e com o fork Pro privado deles) — está em
  `.claude/skills/sync-fork/SKILL.md` naquele repositório. **Não duplicar aquele processo aqui.**
  Se algum dia formos nós a puxar `chatwoot/chatwoot` diretamente (pulando a camada fazer-ai), aí
  sim vale revisitar aquele skill como referência.
- Remotes esperados neste repositório: `origin` = `stephaniemoreira-eng/chat-up2`, e um remote
  apontando para `fazer-ai/chatwoot` (adicionar se ainda não existir:
  `git remote add fazer-ai https://github.com/fazer-ai/chatwoot.git`).
- Branch base de trabalho: `fix/agent-bots-current-account-order` (ou o que vier a substituí-la
  como branch principal da fazer.ai com as correções aplicadas) — nunca `develop` puro.

## Princípio

O fork foi desenhado para que a lista de arquivos nativos editados seja **fechada e conhecida**
(ADR-0001, seção 5). O playbook depende disso: se um merge conflita **fora** dessa lista, o sinal
não é "resolver o conflito" — é "uma fase vazou acoplamento, corrigir o desenho".

## 1. Inspeção antes de mergear

Sempre olhar antes de escrever:

```bash
git fetch fazer-ai
git log --oneline HEAD..fazer-ai/main | head -50              # o que vem
git diff --stat HEAD fazer-ai/main -- config/routes.rb
git merge --no-commit --no-ff fazer-ai/main                    # não commita
git status --short | grep '^UU\|^AA'                           # arquivos em conflito
git merge --abort                                               # sempre abortar esta inspeção
```

Classificar cada conflito:

- **Está na lista fechada do ADR-0001?** → resolver conforme a seção 3.
- **Não está?** → investigar por que. Provavelmente uma fase editou um nativo que não deveria.

## 2. Executar o merge

```bash
git checkout -b merge/fazer-ai-<data-ou-versao>
git merge fazer-ai/main
```

## 3. Resolução por arquivo

### `db/schema.rb` — conflita sempre, por construção

Nunca resolver à mão. Regenerar:

```bash
git checkout --theirs db/schema.rb     # aceita o schema do upstream
bundle exec rails db:migrate           # reaplica nossas migrations por cima
git add db/schema.rb
```

Depois confirmar que as nossas tabelas sobreviveram:

```bash
grep -n "sales_pipelines\|sales_stages" db/schema.rb
```

### `config/features.yml` e `app/models/concerns/featurable.rb` — não deveriam conflitar nunca

Decisão registrada em ADR-0001 (seção 4, revisada): as flags do fork **não vivem** nesses
arquivos. Elas ficam em `settings` jsonb via `store_accessor`, em
`enterprise/app/models/enterprise/concerns/account.rb` — arquivo que já está na lista fechada por
outro motivo (associações). `config/features.yml` e `app/models/concerns/featurable.rb`
permanecem **byte-idênticos** ao que vier de `fazer-ai/chatwoot`.

Se qualquer um desses dois arquivos aparecer em conflito, isso é sinal de que alguma fase futura
violou a decisão do ADR-0001 e voltou a editá-los diretamente — corrigir a violação, não o
conflito. A resolução correta de um conflito genuíno nesses arquivos é sempre **aceitar
integralmente o lado `fazer-ai/main`** (`git checkout --theirs`), nunca combinar.

Verificar depois:

```bash
bundle exec rspec spec/enterprise/models/account_spec.rb   # guarda das flags settings-jsonb do fork
```

### `config/routes.rb`

Deve conflitar raramente (nossa edição é uma linha). Manter o `draw :sales` dentro de
`scope module: :accounts`. Nossas rotas em si estão em `config/routes/sales.rb`, que nunca conflita.

### `lib/events/types.rb`, `lib/filters/filter_keys.yml`, `enterprise/app/models/enterprise/*.rb`

Conflitos de append. Manter os dois lados. Nos módulos `Enterprise::*`, atenção para preservar o
`super +` do upstream:

```ruby
def actions_attributes
  super + %w[add_sla move_lead_stage assign_lead create_lead_task add_lead_tag]
end
```

### `Sidebar.vue` e `ContactPanel.vue` — hotspots reais

São arquivos grandes que o upstream mexe com frequência. Nossa edição é um bloco contíguo
demarcado por comentário. Resolução: aceitar a versão do upstream e reinserir o bloco.

```bash
git checkout --theirs app/javascript/dashboard/components-next/sidebar/Sidebar.vue
# reinserir o bloco demarcado do fork
```

Se o bloco tiver crescido para além de poucas linhas, extrair mais conteúdo para componentes
próprios em `components-next/Sales/` — o objetivo é que a edição no arquivo nativo permaneça trivial.

### `app/javascript/dashboard/i18n/locale/en/index.js`, `featureFlags.js`, `dashboard.routes.js`, `useUISettings.js`

Conflitos de append, resolução mecânica: manter os dois lados.

## 4. Verificação pós-merge

Nesta ordem — parar no primeiro erro:

```bash
eval "$(rbenv init -)"

bundle install
pnpm install

bundle exec rails db:migrate
git diff --stat db/schema.rb                  # revisar o que mudou no schema

bundle exec rubocop --parallel
bundle exec rspec spec/enterprise/models/account_spec.rb   # guarda das flags settings-jsonb do fork
bundle exec rspec spec/enterprise/

pnpm eslint
pnpm test
```

Verificação funcional mínima:

```bash
overmind start -f Procfile.dev
bundle exec rails runner "Account.first.enable_features!('sales_pipeline')"
```

Abrir o dashboard e confirmar: (a) o módulo comercial funciona; (b) **desligando a flag
`sales_pipeline`, o Chatwoot volta a se comportar exatamente como o upstream** — sem item na
sidebar, sem painel na conversa, sem rota acessível. Esse segundo ponto é a prova de que o
acoplamento continua baixo.

## 5. Após o merge

- Conferir o estado da flag `crm_v2` do upstream (ver ADR-0002). Se o upstream lançou um CRM
  próprio, isso é decisão de produto e o ADR-0002 deve ser revisitado.
- Conferir se o upstream adicionou colunas de feature flag novas.
- Se algum conflito apareceu fora da lista fechada do ADR-0001, atualizar a lista **ou** corrigir
  o acoplamento. A lista só serve como contrato se for mantida honesta.

## Nota sobre i18n — invariante não óbvio

Ao adicionar um arquivo de i18n novo (ex.: `sales.json`), **não basta criá-lo em
`locale/en/` e registrá-lo em `locale/en/index.js`.**

`bin/sync_i18n_file_change` (hook de pre-commit, também exposto como `pnpm sync:i18n`) copia
`locale/en/index.js` **verbatim** para os outros 41 diretórios de locale. Como
`app/javascript/dashboard/i18n/index.js` importa 42 locales, qualquer locale cujo `index.js`
importe um `.json` inexistente quebra o build do Vite.

Invariante verificado no upstream 4.16.0: **todos os 42 locales registrados possuem todos os
arquivos que seu `index.js` importa.** (O diretório `locale/zh/` viola isso, mas é órfão —
`i18n/index.js` registra apenas `zh_CN` e `zh_TW`.)

Portanto, ao introduzir um arquivo de i18n novo, semear uma cópia em todos os locales registrados
no mesmo commit:

```bash
cd app/javascript/dashboard/i18n
for l in $(grep "^import .* from './locale/" index.js | sed "s|.*/locale/||;s|';||"); do
  [ -f "locale/$l/sales.json" ] || cp locale/en/sales.json "locale/$l/sales.json"
done
```

O Crowdin substitui essas cópias por traduções reais depois. Verificar antes de commitar:

```bash
cd app/javascript/dashboard/i18n
for l in $(grep "^import .* from './locale/" index.js | sed "s|.*/locale/||;s|';||"); do
  grep -o "from './[a-zA-Z]*\.json'" "locale/$l/index.js" | sed "s|from './||;s|'||" \
    | while read -r f; do [ -f "locale/$l/$f" ] || echo "MISSING $l/$f"; done
done
```

## Notas sobre CI

- Gate principal: `.github/workflows/run_foss_spec.yml` — rubocop, eslint, `pnpm test:coverage` e
  rspec shardeado em 16 contra `pgvector/pgvector:pg16` + `redis:alpine`.
- Títulos de PR seguem Conventional Commits (`lint_pr.yml`).
- `deploy_check.yml` aponta para infra Heroku do upstream (`chatwoot-pr-<N>.herokuapp.com`) e está
  desabilitado neste fork. Se um merge o reativar, desabilitar de novo.
