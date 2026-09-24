# CP-16B (P2-VAL-19; SSOT §16.1, §23.1, §28.15). Decisão da Stéphanie em 24/09/2026 para a falha do
# Calendar ao agendar:
#
#   "SE FALHAR, AGUARDAR E TENTAR MAIS UMA VEZ EM SILÊNCIO, COM MAIS UMA FALHA > MENSAGEM DE QUE O
#    DANILO VAI ENTRAR EM CONTATO EM BREVE E REGISTRAR NO CAMPO COMO CALLBACK DANILO."
#
# Quem espera e tenta de novo é o up2-agents (a ferramenta `criar_evento`/`atualizar_evento` da
# Lavínia), porque é ele que tem o turno aberto e o tempo de espera (ENV
# ENGINE_CALENDAR_RETRY_DELAY_MS lá). Este módulo é a metade do Engine: cada TENTATIVA tem a sua
# própria entrada no ledger do turno (TurnIdempotency), para que
#
# - a 1ª tentativa continue com a chave de sempre (`ferramenta:criar_evento` + turn_id, CP-10) e a
#   2ª ganhe a sua (`ferramenta:criar_evento:tentativa_2` + turn_id) -- replay de qualquer uma devolve
#   o resultado guardado, sem outra chamada ao Calendar (no máximo DUAS chamadas por turno, como a
#   decisão manda);
# - a 2ª tentativa nunca corra por cima da 1ª: se a 1ª ainda está rodando (ex.: o up2-agents desistiu
#   por timeout mas o Rails seguiu), a 2ª NÃO chama o Calendar e volta como recusa comum -- sem a marca
#   `falha_calendar`, então não vira callback; o turno termina em silêncio + nota (28.15) e nenhum
#   evento duplicado nasce;
# - se a 1ª na verdade deu certo (o up2-agents é que não viu a resposta), a 2ª devolve esse sucesso
#   em vez de "reunião já existia".
module OperationalEngine
  module CalendarRetryAttempt
    SEGUNDA_TENTATIVA = 2
    EM_PROCESSAMENTO = { ok: false, reason: 'primeira tentativa ainda em processamento' }.freeze

    # Falhas de rede da chamada ao up2-agents/Google (HTTParty não as embrulha): também são falha do
    # Calendar -- nada foi confirmado no Engine.
    NETWORK_ERRORS = [
      HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Timeout::Error,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError
    ].freeze

    def self.second?(tentativa)
      tentativa.to_s == SEGUNDA_TENTATIVA.to_s
    end

    def self.operation(base_operation, tentativa)
      second?(tentativa) ? "#{base_operation}:tentativa_#{SEGUNDA_TENTATIVA}" : base_operation
    end

    # Para a 2ª tentativa: o que a 1ª deixou no ledger deste turno. nil = pode chamar o Calendar.
    def self.previous_outcome(conta_id:, base_operation:, turn_id:, tentativa:)
      return nil unless second?(tentativa) && turn_id.present?

      record = OperationalEngine::IdempotencyRecord.find_by(
        conta_id: conta_id, event_type: base_operation,
        external_source: OperationalEngine::TurnIdempotency::EXTERNAL_SOURCE, external_id: turn_id
      )
      return nil if record.nil?
      return EM_PROCESSAMENTO.dup if record.status_received?

      stored = (record.result || {}).deep_symbolize_keys
      stored if record.status_processed? && stored[:ok]
    end
  end
end
