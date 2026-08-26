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
