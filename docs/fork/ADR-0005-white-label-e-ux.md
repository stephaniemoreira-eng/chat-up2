# ADR-0005 — Marca própria do Up Sales: o que é nosso, o que é licença da fazer.ai

- **Status:** aceito (parcialmente bloqueado)
- **Data:** 2026-09-09

## Contexto

Com o produto funcionalmente completo, o que faltava antes de 14/09 era o painel **parecer** um
produto próprio e ser entendível por quem nunca o usou. O ADR-0004 já registrava o tema
("Branding total (marca UP2 substituindo o Chatwoot por completo)") como *"registrado, não
decidido, não priorizado"*. Este ADR fecha aquela pendência.

Duas descobertas de 2026-09-09 moldaram a decisão.

### 1. Existe um Manual de Marca oficial da UP2, e ele fala de dashboards

`G:\Meu Drive\UP2\UP2 - Marca\UP2-Manual-de-Marca.pdf` (v1.0) define a paleta — Petroleum Ink
`#142B33` (estrutura), Copper Vermilion `#D95B3D` (intervenção), Mineral Ivory `#F3EFE7` (base),
Steel `#6E7D82` (dados), Mineral Sage `#89C7C2` (apoio) — e, mais importante, uma **lógica
funcional de cor**: *"Petroleum é estrutura, Copper é intervenção. O Copper aparece quando algo é
identificado, ativado, corrigido, destacado ou recuperado."* A proporção recomendada reserva
apenas 4% para o Copper, e a seção de sistema gráfico é explícita sobre leitura de dados:
*"nunca colorir todas as barras: o Copper indica o dado que exige decisão."*

O painel usava `#2781F6` (azul), que o próprio manual classifica como uso incorreto ("trocar as
cores da paleta"). A tipografia oficial é **Sora**, com **Inter** aceita explicitamente como
substituta.

### 2. O white-label da instalação é recurso pago do fork da fazer.ai

Três camadas independentes confirmam isso no código:

- As 11 chaves de marca (`INSTALLATION_NAME`, `LOGO*`, `BRAND_*`, `DISPLAY_MANIFEST`,
  `TERMS_URL`, `PRIVACY_URL`) entram no banco com `locked = true`
  (`lib/config_loader.rb:62-67` + `app/models/installation_config.rb:81-84`), e a tela de
  configurações do Super Admin lista só `locked: false` (`installation_config.rb:66`).
- Existe uma aba "Custom Branding" que edita exatamente essas chaves
  (`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:21-35`), mas ela
  é liberada só quando `ChatwootHub.pricing_plan != 'community'` — e a instância está em
  `community` (`config/installation_config.yml:316-317`).
- Mesmo gravando direto no banco, `Internal::ReconcilePlanConfigService` reverte as chaves para os
  valores do Chatwoot **diariamente** enquanto o plano for `community`, e exibe um banner
  *"Unauthorized premium changes detected"* no Super Admin.

O caminho documentado pela própria fazer.ai (`CUSTOM_BRANDING.md`) é variáveis de ambiente +
`rails branding:update` — que o `post_start` do `docker-compose.coolify.yaml:45-49` já executa a
cada start do container. Sem o plano liberado, isso vira um cabo de guerra: o start aplica, o cron
diário desfaz.

## Decisão

1. **Não contornar a trava de licenciamento por código.** Neutralizar
   `ReconcilePlanConfigService` ou forçar `INSTALLATION_PRICING_PLAN` seria violar o licenciamento
   do fork que a UP2 usa. O caminho é comercial: confirmar com a fazer.ai se o contrato inclui
   marca própria e pedir o plano liberado. Enquanto isso, a marca da instalação (tela de login,
   título da aba, favicon, rodapé de e-mail, "Powered by" do widget) permanece como está.

2. **Aplicar a identidade onde o fork já nos dá controle**, que é a maior parte do painel:
   `Account#settings['brand_color']` alimenta o CSS var `--dynamic-account-brand`
   (`Sidebar.vue:246-256`), que por sua vez alimenta o token `n-brand` usado em botões, links e
   estados ativos de toda a interface; `brand_logo_url` troca o logo da barra lateral. Nenhum dos
   dois passa pela trava premium.

3. **Traduzir a lógica de cor do manual para o painel**, em vez de só trocar hexadecimais: a faixa
   `revisao_prioritaria` do pré-score e o pilar mais fraco do SCAN — literalmente "o dado que
   exige decisão" — recebem Copper; o resto fica neutro
   (`app/javascript/dashboard/components-next/Sales/scanVisuals.js`, compartilhado entre o card do
   Kanban e o painel de detalhe, que antes duplicavam o mapa de cores).

4. **Adiar a troca para Sora.** As fontes deste projeto são auto-hospedadas via `@font-face`
   (`app/javascript/shared/assets/fonts/inter.scss`), então adotar Sora exige adicionar os
   `.woff2` ao repo e não um `<link>` de CDN. Como o manual aceita Inter como substituta oficial,
   a troca sai desta rodada — é ganho estético com custo de asset, não bloqueio.

5. **Esconder do menu o que não é fluxo comercial**: Caixa de Entrada (segunda visão das mesmas
   conversas), Chat Interno e Central de Ajuda. Implementado como um filtro por nome no fim da
   montagem de `menuItems` (`Sidebar.vue`), e **não** removendo as entradas nativas — mantém o
   código do upstream intacto e reduz o atrito de merge que o ADR-0001 se preocupa em conter.
   Relatórios ficou como estava: suas rotas já exigem `administrator`/`report_manage`
   (`reports.routes.js:29`).

6. **Tratar "não sei o que está acontecendo" como bug de UX, não como polimento.** O serializer
   escondia o status `pendente` do Scan (devolvia `nil` tanto para "nunca escaneado" quanto para
   "escaneando agora"), então um lead recém-criado ficava visualmente idêntico a um lead sem Scan
   durante o quase um minuto que o PageSpeed leva. Corrigido no `else` de
   `_sales_lead.json.jbuilder`, com estado "calculando" no card e no painel. E como não existe
   listener para o evento `SALES_LEAD_UPDATED` (`lib/events/types.rb:96` é despachado mas nunca
   consumido), o board faz polling silencioso de 8s enquanto houver lead pendente — sem isso o
   score só aparecia recarregando a página na mão.

## Consequências

- A parte visível do painel fica com a identidade UP2 sem depender de negociação, mas **a tela de
  login continua dizendo "Chatwoot"** até a licença ser resolvida. Isso é aceitável para uso
  interno e para demonstração assistida; não é aceitável para revenda white-label, e precisa estar
  claro para quem vende.
- O item de maior impacto real da auditoria não é visual e não depende da licença: se
  `MAILER_SENDER_EMAIL` não estiver definida no ambiente, todo e-mail respondido por um agente sai
  como `Chatwoot <accounts@chatwoot.com>` (`app/mailers/conversation_reply_mailer.rb:9`) — é o que
  o cliente do cliente recebe na caixa de entrada.
- Fica registrado como fora de escopo desta rodada: varredura dos textos nativos que citam
  "Chatwoot" (Integrações, criação de canal, MFA, auditoria), o painel Super Admin, a imagem
  compartilhável do "Resumo do ano", e trocar o branco puro pelo Mineral Ivory no tema claro
  (mudaria o tema inteiro perto do prazo).
- Decisão consciente de **nunca** renomear os identificadores internos (`window.chatwootConfig`,
  classes `woot-*`, `sdk.js`): quebraria o script de instalação já embutido no site de cada
  cliente, e não é visível para o usuário final.
