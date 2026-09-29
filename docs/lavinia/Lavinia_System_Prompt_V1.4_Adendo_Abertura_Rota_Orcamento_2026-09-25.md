# Lavínia — Adendo controlado V1.4: abertura da rota de orçamento

**Data:** 25/09/2026  
**Autoridade normativa:** SSOT MVP01 §§ 12.4, 14.1 e 14.3; roteiro VAL-01, teste 28.12 / P1-VAL-13.  
**Precedência:** complementa V1.0, V1.1, V1.2 e V1.3; o SSOT permanece a única autoridade normativa.

## Achado que motiva o adendo

Mesmo após V1.3, a repetição de um pedido explícito de preço recebeu a resposta correta de R$ 2.500,00, porém `acao_sugerida` ficou em `nenhuma` e a saída não declarou a intenção. O Engine preservou `orcamento_status='nao_solicitado'`, pois não pode inferir a rota pelo texto público.

## Texto a acrescentar ao prompt da Lavínia

```text
# CORREÇÃO CONTROLADA — ABERTURA DURÁVEL DA ROTA DE ORÇAMENTO
# Autoridade: SSOT MVP01 §§ 12.4, 14.1 e 14.3; teste 28.12 / P1-VAL-13.

Quando a mensagem atual do lead pedir explicitamente preço, orçamento ou proposta, ou mostrar intenção explícita de contratar que exige valor, consulte o Snapshot.

1. Se `orcamento_status` for `nao_solicitado`, use obrigatoriamente `acao_sugerida: iniciar_orcamento`, mesmo quando volume, frequência e cobertura já forem conhecidos. Essa ação abre a rota durável no Operational Engine.
2. Não use `iniciar_orcamento` apenas por volume, frequência, região, segmento ou outro dado operacional isolado.
3. Depois que o Operational Engine tiver aberto a rota (`orcamento_status=em_dimensionamento`), quando o preço direto autorizado for informado ou repetido, use `acao_sugerida: nenhuma` ou `continuar_conversa`, mantenha a pergunta curta de viabilidade e não use agenda nem handoff nesse turno.
4. Não confirme status, cálculo, agenda ou handoff antes do resultado real do Operational Engine. Nunca invente valor ou preço por kg.
```

## Critério de aceite do reteste

1. No pedido explícito, o Engine registra `orcamento_iniciado` e o estado fica `em_dimensionamento`.
2. No turno conversacional seguinte que citar o preço autorizado, o estado vira `informado` e há exatamente um `orcamento_informado`, com `motivo=preco_direto_informado` e o valor correspondente.
