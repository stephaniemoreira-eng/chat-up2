# ADR-0004 — Up Sales vive dentro do `chat-up2`, não num app separado

- **Status:** aceito
- **Data:** 2026-08-26

## Contexto

O plano inicial do produto "Up Sales" (CRM white-label multi-tenant, marca própria por cliente)
era um app novo em Next.js/Supabase, consumindo Chatwoot só via API, como um "motor" invisível —
nenhuma tela do Chatwoot apareceria pro usuário. Uma primeira fase desse plano chegou a ser
construída e testada (login, marca por subdomínio, Dashboard, Contatos, Pipeline com colunas
editáveis, banco Supabase próprio).

Duas descobertas mudaram a decisão, com o prazo do projeto reduzido de 18/09 para **14/09**:

1. **"AstraChat"**, uma estrutura que a Stéphanie já tinha disponível, foi confirmada (pelo
   `chatwoot_AstraChat.yaml` do Drive da UP2) como **literalmente uma build do Chatwoot**
   (`astraonline/astrachat`, mesmos comandos Rails, mesmas variáveis de ambiente documentadas
   pelo próprio Chatwoot) — não é um produto à parte com API diferente.
2. Este próprio repositório (`chat-up2`) **já tem um Kanban pronto e funcionando** (módulo
   `Sales::`, ver ADR-0002) e a tela de conversas nativa do Chatwoot já resolve tempo real
   (ActionCable), anexos de áudio/imagem do WhatsApp (Baileys), indicador de digitando — o tipo de
   engenharia que levaria **semanas** pra reconstruir do zero em outro framework.

A insatisfação da Stéphanie com a experiência atual é de **interface** ("não acho intuitiva"),
não de funcionalidade — problema que um reskin resolve bem e uma reconstrução do zero, no prazo
que sobrou, resolveria mal (trocaria "funciona mas feio" por "bonito mas com bugs novos").

## Decisão

**Up Sales é construído dentro do `chat-up2`**, como rotas/módulos aditivos, seguindo o mesmo
padrão já estabelecido pelo módulo `Sales::` (ADR-0001/0002/0003) — nunca editando arquivo nativo
fora da lista auditável do ADR-0001. O trabalho da fase Next.js fica parado (não apagado, só não é
mais o caminho de construção daqui pra frente).

**Namespace de código novo:** `UpSales::`/`up_sales_*` no backend (quando não fizer mais sentido
reaproveitar `Sales::` diretamente), rotas frontend em
`app/javascript/dashboard/routes/dashboard/up-sales/`. Primeira peça construída: marca por conta
(`Account#settings['brand_color']`/`['brand_logo_url']`, ver commit desta mesma data) — segue o
mesmo padrão `store_accessor :settings` já usado por `sales_pipeline_enabled`/`sales_kanban_enabled`
(`enterprise/app/models/enterprise/concerns/account.rb`), e o mesmo padrão de CSS var runtime já
provado pelo branding de `Portal` (`app/views/layouts/_portal_scripts.html.erb`), adaptado pra
rodar do lado do Vue (`Sidebar.vue`) já que o dashboard é uma SPA de vida longa, não uma página
renderizada por requisição.

**Reaproveitado sem trabalho novo:** sessão/login (Pundit), ActionCable, anexos de WhatsApp
(Baileys), o Kanban `Sales::` inteiro, distribuição round-robin nativa
(`AutoAssignment::InboxRoundRobinService`), importação de contatos via CSV nativa
(`POST /api/v1/accounts/:id/contacts/import`).

**Reskin, não reconstrução:** Sidebar, tela de Conversas, e o Kanban `Sales::` — trocar
cor/tipografia/espaçamento e simplificar navegação, dentro dos pontos de toque já auditados
(`Sidebar.vue`, etc.), sem reescrever a lógica que já funciona.

### Fronteira de dados — dois bancos continuam separados, de propósito

A prospecção **própria da UP2** (Fluxo 1/2/3a do n8n, PScore, o Leandro buscando clientes pra
própria UP2) continua no Supabase "BD Up2" — é operação interna da UP2, não do produto Up Sales.
Essa base também segue guardando o cadastro administrativo `public.clientes` (qual cliente é qual
conta Chatwoot / tenant do `agents` / quais dos 3 tipos de agente estão ativos por contrato).

Todo o **dado de CRM de cada cliente** (contatos, leads, pipeline, conversas) do produto Up Sales
vive no banco Postgres do próprio Chatwoot, isolado nativamente por `account_id` — 1 cliente = 1
conta Chatwoot, decisão já tomada antes desta sessão. Não existe (nem deve existir) um terceiro
banco externo para esse dado.

O Supabase criado especificamente pra fase Next.js do Up Sales (`wgxtwtrsfgqhdbqejhej`) fica sem
uso a partir desta decisão.

## Consequências

**Positivas:** reaproveita meses de engenharia já madura (tempo real, anexos, Kanban) em vez de
reconstruir sob pressão de prazo; mantém a fronteira de dado entre operação interna da UP2 e CRM
dos clientes clara e já testada; segue a mesma disciplina aditiva que já provou funcionar pro
módulo `Sales::`.

**Negativas:** o trabalho da fase Next.js (Semana 1, testada) não é reaproveitado como código —
só como aprendizado de schema/UX. Toda tela nova exige entender e respeitar o padrão aditivo do
Chatwoot (Vuex/Pinia, ActionCable, Pundit) em vez do padrão mais simples do Next.js/Server Actions
já dominado nesta sessão.

**A registrar à medida que cada peça nova for construída:** Dashboard, Busca/Prospecção, Super
Admin de configuração de agente, Follow-up (importação + transferência), Calculadora comercial,
Agenda integrada — ver `C:\Users\Stephanie\.claude\plans\swirling-twirling-nest.md` pro plano
semana a semana.

## Estratégia de atualização do fork — já decidida, não é um item em aberto

Pergunta levantada pela Stéphanie em 2026-08-27: manter compatibilidade com atualizações do
Chatwoot (sem quebrar nem perder configuração do fork) vs. parar de puxar atualizações e seguir só
com o projeto próprio, permanentemente divergente.

**Isso já está decidido e documentado — a primeira opção, desde o ADR-0001.** Resumo:

- Merge com o upstream é **manual e deliberado**, nunca automático (`docs/fork/UPSTREAM_MERGE_PLAYBOOK.md`,
  seção "Executar o merge" — um branch `merge/fazer-ai-<data>` por vez, inspecionado antes de
  aplicar).
- A estratégia aditiva do ADR-0001 (lista fechada de arquivos nativos tocados, seção 5) existe
  **exatamente pra isso**: manter uma superfície de conflito pequena e conhecida, pra que puxar uma
  versão nova do Chatwoot não quebre nem apague nada do fork. O playbook trata qualquer conflito
  fora dessa lista como bug de acoplamento a corrigir, não como conflito a resolver na mão.
- `db/schema.rb`, `config/features.yml` e outros arquivos sensíveis têm procedimento de merge
  próprio documentado (seção 3 do playbook) pra garantir que nossas tabelas/flags sobrevivem.

Não precisa de nova decisão — só reforçar, se um dia isso for questionado de novo, que **o caminho
escolhido é continuar puxando atualizações do Chatwoot** (via `fazer-ai/chatwoot`, não direto do
`chatwoot/chatwoot` — ver playbook seção "Este é um fork de dois níveis"), nunca automaticamente,
sempre com o checklist de verificação pós-merge do playbook.

## Branding total (marca UP2 substituindo o Chatwoot por completo) — registrado em 2026-08-27, não decidido

Pergunta levantada pela Stéphanie na mesma conversa: ir além da marca dinâmica por conta
(`brand_color`/`brand_logo_url`, já construída) e fazer o Chatwoot **assumir a marca da UP2/Up
Sales por completo** — "mesmo que isso seja espelhamento" (ou seja, mascarar a identidade visual
do Chatwoot, não necessariamente reescrever nada por baixo).

**O que já existe (escopo atual, por conta, dinâmico):** cor de marca e logo no Sidebar da SPA do
dashboard (`Account#settings`, ver corpo desta ADR acima).

**O que NÃO existe ainda** (identidade "Chatwoot" ainda aparece, fixa, fora da SPA por-conta):
- Painel Super Admin nativo (`/super_admin`) — texto fixo "Chatwoot Admin Dashboard" e logo
  (`app/views/super_admin/application/_navigation.html.erb`).
- Tela de login/signup, PWA manifest, favicon, `<title>` padrão, e-mails transacionais
  (convite, redefinição de senha, notificação) — todos nativos, ainda não auditados nem tocados
  por nenhuma ADR deste fork.
- Rodapé/links de central de ajuda e termos que apontam pra domínios do Chatwoot.

**Por que isso é uma decisão à parte, não só "mais uma tela":** cada arquivo nativo tocado pra
mascarar a marca (manifest, views de e-mail, layout do super_admin, etc.) é mais um item na lista
fechada do ADR-0001 — aumenta a superfície de conflito de merge com o upstream (ver seção acima).
Não é proibitivo, mas é meio, não fim: precisa entrar na lista auditada e ser mantido a cada merge,
como qualquer outro ponto de toque.

**Status: registrado, não decidido, não priorizado.** Fica para uma conversa futura decidir o
alcance (só o essencial — título, favicon, e-mails — ou also o painel Super Admin inteiro) e abrir
uma ADR própria (ADR-0006 ou o próximo número livre) quando for priorizado.
