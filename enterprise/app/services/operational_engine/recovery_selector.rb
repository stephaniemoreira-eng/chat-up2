# CP-13 (P1-VAL-12; SSOT §15.6, §15.7, §6.4): a fila de Recovery -- leads cuja próxima
# tentativa (ou passo de esgotamento) já está elegível.
#
# Prioridade (§15.7): 1) quem já conversava e parou; 2) quem nunca respondeu (lead em Contatado --
# mesmo critério do RecoveryCadence.tipo). Dentro do grupo, FIFO por horário de elegibilidade
# (proxima_recuperacao_em ASC), desempate estável por lead_id. Materializado em Array (nunca
# find_each, que troca o ORDER BY pela PK).
#
# NÃO filtra lead_status/modo/nao_contatar/aguardando aqui de propósito: quem venceu mas não pode mais receber
# recovery precisa passar pela revalidação do dispatcher, que interrompe o ciclo (timer que não faz
# mais sentido não fica pendurado para sempre).
module OperationalEngine
  class RecoverySelector
    LIMITE = 100

    def self.vencidos(conta_id:, agora: Time.current, limite: LIMITE)
      OperationalEngine::Lead
        .where(conta_id: conta_id)
        .where(proxima_recuperacao_em: ..agora)
        .order(Arel.sql("CASE WHEN etapa_prospect = 'contatado' THEN 1 ELSE 0 END ASC"), proxima_recuperacao_em: :asc, lead_id: :asc)
        .limit(limite)
        .to_a
    end
  end
end
