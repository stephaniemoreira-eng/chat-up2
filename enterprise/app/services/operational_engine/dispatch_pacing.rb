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

    # A tentativa mais recente de originação nesta inbox (qualquer ativação, em qualquer estado).
    def self.last_attempt_at(inbox_id)
      key = OperationalEngine::OriginationActivation::KEY
      value = ::Conversation.where(inbox_id: inbox_id, created_at: LOOKBACK.ago..)
                            .maximum(Arel.sql("(additional_attributes -> '#{key}' ->> 'last_attempt_at')::timestamptz"))
      value&.in_time_zone
    end
  end
end
