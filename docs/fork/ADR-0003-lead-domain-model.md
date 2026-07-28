# ADR-0003 — Modelo de domínio do Lead

- **Status:** aceito
- **Data:** 2026-07-28

## Contexto

O requisito diz "cada conversa poderá possuir um Lead", e ao mesmo tempo pede que o Lead tenha
histórico e timeline unificada. Essas duas coisas puxam em direções opostas, então a cardinalidade
precisava ser decidida explicitamente antes de qualquer migration.

Três desenhos possíveis:

1. **Lead 1:1 com Conversation** — simples, mas fragmenta o histórico: o mesmo cliente voltando a
   falar gera um lead novo, e a timeline unificada perde sentido.
2. **Lead pertence ao Contact, N conversas** — o histórico comercial acompanha a pessoa.
3. **Lead independente, N contatos e N conversas** — modelo de CRM B2B completo, com um negócio
   tendo vários interlocutores. Mais poderoso, muito mais complexo em UI e permissões.

## Decisão

**Opção 2:** `Contact` tem N `Sales::Lead`; cada Lead se liga a N conversas.

```
Contact 1 ─── N Sales::Lead
                  │
                  ├── N Sales::LeadConversation ─── 1 Conversation   (unique em conversation_id)
                  ├── N Sales::StageTransition
                  ├── N Sales::Task
                  ├── N Sales::Activity
                  └── labels via Labelable
```

Um contato pode ter vários negócios abertos ao longo do tempo; cada conversa pertence a no máximo
um deles.

### Ligação com Conversation via tabela associativa, não via coluna

`sales_lead_conversations` com índice **único em `conversation_id`** e índice em `sales_lead_id`,
em vez de uma coluna `conversations.sales_lead_id`. Razões:

1. `conversations` é a tabela mais quente do sistema; não a engordamos.
2. Não exige migration em tabela nativa — sem `ALTER TABLE` custoso e sem conflito adicional.
3. O índice único entrega a invariante "uma conversa pertence a no máximo um Lead" no nível do banco.
4. `Conversation` ganha `has_one :sales_lead, through: :sales_lead_conversation` pelo concern
   `Enterprise::Concerns::Conversation`, sem tocar em `app/models/conversation.rb`.

### O Lead não duplica dados do Contact

O requisito lista Nome, Empresa, Email e Telefone como campos do Lead. Eles **não** viram colunas
de `sales_leads`: já existem em `contacts` (`name`, `email`, `phone_number`, `company_id` →
`Company`). `Sales::Lead` delega esses campos ao `contact`.

Duplicá-los criaria dois donos da verdade e um problema de sincronização permanente — o tipo de
decisão que parece inofensiva na migration e custa caro seis meses depois.

`sales_leads` carrega apenas o que é comercial e próprio do negócio:

```
title, source, assignee_id, pipeline_id, stage_id,
value_cents, currency, probability, status,
expected_close_date, closed_at, stage_changed_at, last_activity_at,
position, notes, custom_attributes (jsonb), additional_attributes (jsonb)
```

### Timeline por composição, não por tabela espelho

`Sales::Leads::TimelineBuilderService` funde, em tempo de leitura, streams que já existem:
mensagens das conversas ligadas, `Note`s do contato, anexos, `Sales::StageTransition`,
`Sales::Task` e `Sales::Activity` — ordenando por timestamp com paginação por cursor.

Não há tabela replicando mensagens. Isso evita duplicação de storage e, principalmente, evita a
classe inteira de bugs de sincronização entre a mensagem real e sua cópia na timeline.

`Sales::Activity` existe só para eventos que não têm outro dono: ação executada por automação,
ação executada pela IA.

### Ordenação no Kanban

`sales_leads.position` como `decimal`, com **midpoint insertion** (nova posição = média entre os
vizinhos). Mover um card é **um único UPDATE**, sem renumerar a coluna inteira. Um job periódico
rebalanceia quando a precisão decimal degrada. A escrita usa `MutexApplicationJob` (lock
distribuído em Redis, já disponível em `app/jobs/mutex_application_job.rb`) para movimentações
concorrentes na mesma etapa.

## Consequências

**Positivas:** histórico comercial coerente por pessoa; uma única fonte de verdade para dados de
contato; timeline sem duplicação; nenhuma migration em tabela nativa; movimentação de card em O(1).

**Negativas:** a timeline composta é mais caro em leitura do que uma tabela materializada —
mitigado com cursor e limite por fonte, e revisável para materialização se a medição em produção
justificar. E consultas de lead frequentemente precisam de `join` com `contacts` para exibir
nome/email, exigindo `includes(:contact)` disciplinado para evitar N+1.

**Não escolhido, mas viável depois:** a opção 3 (Lead com N contatos) pode ser alcançada
acrescentando uma tabela `sales_lead_contacts` sem quebrar este desenho — `belongs_to :contact`
viraria o "contato principal".
