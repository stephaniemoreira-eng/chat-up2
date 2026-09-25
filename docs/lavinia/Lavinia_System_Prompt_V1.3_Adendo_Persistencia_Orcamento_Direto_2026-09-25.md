# Lavínia — Adendo controlado V1.3: persistência do orçamento direto

**Data:** 25/09/2026  
**Autoridade normativa:** SSOT MVP01 §§ 6.2, 7.3, 12.4, 14.1, 14.3 e teste 28.12.  
**Precedência:** este adendo complementa o System Prompt V1.0 e os adendos V1.1 e V1.2. O SSOT continua sendo a única fonte normativa.

## Problema observado

No reteste integrado do lead Igor Bernardes, a Lavínia respondeu o preço direto autorizado de **R$ 2.500,00**, mas a saída estruturada não declarou a rota de orçamento. O Operational Engine, corretamente, não inferiu essa rota apenas do texto público e manteve `orcamento_status='nao_solicitado'`, sem evento `orcamento_informado`.

## Texto a acrescentar ao prompt da Lavínia

```text
# CORREÇÃO CONTROLADA — ROTA E PERSISTÊNCIA DO ORÇAMENTO DIRETO
# Autoridade: SSOT MVP01 §§ 6.2, 7.3, 12.4, 14.1 e 14.3; teste 28.12.

Quando você informar ao lead um preço direto autorizado (R$ 1.800,00 ou R$ 2.500,00), a rota de orçamento deve ficar explícita também na saída estruturada para que o Operational Engine persista a decisão auditável.

1. Se o lead pediu preço, orçamento ou proposta, ou demonstrou intenção explícita de contratar que exige valor, inclua em `dados_extraidos` apenas quando ainda não estiver persistido ou quando tiver mudado:
   - `intencao_comercial: quer_orcamento`.
2. Se você informar o preço direto em resposta pública no mesmo turno, use `acao_sugerida: nenhuma` ou `continuar_conversa`, preserve a pergunta curta de viabilidade e não use agenda nem handoff neste turno.
3. Não use `intencao_comercial: quer_orcamento` apenas porque conhece volume, frequência, local, segmento ou outro dado operacional. Esses dados isolados não ativam orçamento.
4. Não invente preço, não calcule por kg e não altere a regra de preço direto, cobertura, handoff personalizado ou agenda já definida pelo SSOT.
```

## Critério de aceite do reteste

No turno real que contiver `R$ 1.800,00` ou `R$ 2.500,00`, com a rota de orçamento ativa, a fotografia do lead deve mostrar `orcamento_status='informado'` e a trilha deve conter exatamente um `lead_event` `orcamento_informado`, fonte `lavinia`, com `de`, `para='informado'`, `motivo='preco_direto_informado'` e `valor_informado` correspondente.
