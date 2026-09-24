# CP-02 (P1-024-03; SSOT §15.6 "evita rajadas", §25 `intervalo_dispatch_inbox`): o espaçamento
# mínimo entre duas primeiras abordagens na MESMA inbox de Prospecção. A capacidade (BacklogCapacity)
# diz QUANTAS ainda cabem na janela; isto diz QUANDO a próxima pode sair -- 10 vagas livres não são
# licença para 10 mensagens no mesmo instante, e um job atrasado/reiniciado não recupera o tempo
# perdido com um blast (a referência é sempre a última tentativa real na inbox).
#
# O SSOT deixa o valor como "parametrizável/calibrar": ele vive num lugar só
# (ENV UP_SALES_DISPATCH_INTERVAL_SECONDS) com um padrão técnico conservador --
# calibrar é configuração, não reescrita do motor.
module OperationalEngine
  class DispatchPacing
    DEFAULT_INTERVAL_SECONDS = 300
    LOOKBACK = 30.days

    def self.interval
      ENV.fetch('UP_SALES_DISPATCH_INTERVAL_SECONDS', DEFAULT_INTERVAL_SECONDS).to_i.seconds
    end

    def self.allows?(inbox_id:, now: Time.current)
      last = last_attempt_at(inbox_id)
      last.nil? || last <= now - interval
    end

    # A tentativa automática mais recente nesta inbox (qualquer ativação, em qualquer estado).
    #
    # CP-13 (P1-VAL-12; SSOT §15.6 "uma fila operacional de saída" coordenando primeira abordagem E
    # recovery WhatsApp): conta também as tentativas de recovery (RecoveryActivation) da inbox --
    # abertura e recovery disputam o mesmo espaçamento, nunca saem juntas. A conversa de recovery pode
    # ser antiga (criada há mais de LOOKBACK), então o recorte dela é pela última atividade.
    def self.last_attempt_at(inbox_id)
      [origination_attempt_at(inbox_id), recovery_attempt_at(inbox_id)].compact.map(&:in_time_zone).max
    end

    def self.origination_attempt_at(inbox_id)
      ::Conversation.where(inbox_id: inbox_id, created_at: LOOKBACK.ago..).maximum(attempt_sql(OperationalEngine::OriginationActivation::KEY))
    end

    def self.recovery_attempt_at(inbox_id)
      ::Conversation.where(inbox_id: inbox_id, last_activity_at: LOOKBACK.ago..).maximum(attempt_sql(OperationalEngine::RecoveryActivation::KEY))
    end

    def self.attempt_sql(key)
      Arel.sql("(additional_attributes -> '#{key}' ->> 'last_attempt_at')::timestamptz")
    end
    private_class_method :origination_attempt_at, :recovery_attempt_at, :attempt_sql
  end
end
