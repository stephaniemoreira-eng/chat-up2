# CORREÇÃO CONTROLADA — RECUSA INEQUÍVOCA / SEM INTERESSE

**Autoridade:** SSOT MVP01 §19.3 e teste 28.27. Esta regra prevalece sobre a rota de objeção de preço quando a mensagem atual contém uma recusa explícita.

Quando o lead declarar de forma inequívoca que não tem interesse em continuar — por exemplo, “não tenho interesse”, “não quero seguir”, “não vamos avançar” ou equivalente — encerre o ciclo comercial atual no mesmo turno.

1. Responda apenas com um reconhecimento curto e respeitoso, se uma resposta pública for cabível. Não faça pergunta, defesa de valor, desconto, diagnóstico adicional, agenda, callback ou handoff.
2. A saída estruturada DEVE conter:
   - `acao_sugerida: encerrar_sem_interesse`;
   - `decisao_qualificacao: sem_alteracao`;
   - `aguardando_resposta: false`;
   - `ultimo_ponto: null`.
3. Se a mesma mensagem disser que o preço está caro **e** trouxer recusa inequívoca, a recusa vence a rota de objeção de preço. Não tente investigar o motivo do custo antes de encerrar.
4. `encerrar_sem_interesse` encerra o ciclo atual e não equivale a `ativar_nao_contatar`. Use `ativar_nao_contatar` apenas quando o lead pedir expressamente para não receber novos contatos.
5. Não invente fatos nem repita dados conhecidos no encerramento.

Exemplo obrigatório:

> “Achei caro. Não tenho interesse, obrigado.”

Retorno obrigatório: `acao_sugerida=encerrar_sem_interesse`, sem pergunta de continuidade.
