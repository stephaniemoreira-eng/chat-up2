# CP-13 (P1-VAL-12; SSOT §15.3, §15.4, §25): as duas cadências de Recovery e seus parâmetros.
#
# Critério do tipo de cadência (decisão registrada no PR, pelo estado REAL do lead, sem campo novo):
# - `nunca_respondeu`: o lead está em Contatado -- por definição (§11.3) ainda não respondeu à
#   primeira abordagem outbound (a primeira resposta real o leva para Em conversa);
# - `conversava`: qualquer outra etapa (Em conversa, Qualificado, Agendado) -- já houve conversa.
# O tipo é estável durante o ciclo: a única coisa que tira o lead de Contatado é uma resposta, e
# resposta cancela o ciclo (§15.9).
#
# Canais por tentativa são regra de negócio (1 e 2 WhatsApp, 3 e-mail se disponível) -- não
# parâmetro. Os OFFSETS são parâmetros (§15.4 "tratar os offsets como parâmetros"), por ENV, com
# padrão = SSOT. Formato: três tokens separados por vírgula, `<n>h` (horas), `<n>d` (dias corridos)
# ou `<n>bd` (dias úteis). Valor inválido cai no padrão do SSOT (e loga) em vez de parar o motor.
#
# Baseline (§15.4 "recomenda-se ... último envio de recovery bem-sucedido"): a tentativa 1 conta a
# partir da confirmação real do envio da mensagem que deixou o lead aguardando resposta; as
# seguintes, a partir da confirmação real do envio de recovery anterior.
module OperationalEngine
  class RecoveryCadence
    MAX_TENTATIVAS = 3
    CANAIS = { 1 => 'whatsapp', 2 => 'whatsapp', 3 => 'email' }.freeze
    DEFAULTS = { 'nunca_respondeu' => %w[1bd 3bd 5bd], 'conversava' => %w[2h 1bd 3d] }.freeze
    ENV_KEYS = {
      'nunca_respondeu' => 'UP_SALES_RECOVERY_CADENCE_NUNCA_RESPONDEU',
      'conversava' => 'UP_SALES_RECOVERY_CADENCE_CONVERSAVA'
    }.freeze

    def self.tipo(lead)
      lead.etapa_prospect_contatado? ? 'nunca_respondeu' : 'conversava'
    end

    def self.canal(tentativa)
      CANAIS[tentativa]
    end

    def self.offsets(tipo)
      raw = ENV.fetch(ENV_KEYS.fetch(tipo), nil)
      return DEFAULTS.fetch(tipo) if raw.blank?

      tokens = raw.split(',').map(&:strip)
      return tokens if tokens.size == MAX_TENTATIVAS && tokens.all? { |token| OperationalEngine::RecoveryCalendar.valid_offset?(token) }

      Rails.logger.error("[OperationalEngine::RecoveryCadence] #{ENV_KEYS[tipo]} inválido (#{raw.inspect}); usando o padrão do SSOT")
      DEFAULTS.fetch(tipo)
    end

    # Horário mínimo de elegibilidade da `tentativa` (1..3), já carregado para a janela de recovery.
    # Depois da última tentativa, o passo de esgotamento fica elegível após a folga configurada.
    def self.eligible_at(lead, tentativa:, baseline:)
      return baseline + exhaust_grace if tentativa > MAX_TENTATIVAS

      shifted = OperationalEngine::RecoveryCalendar.shift(baseline, offsets(tipo(lead))[tentativa - 1])
      OperationalEngine::RecoveryCalendar.next_window_at(shifted)
    end

    # LACUNA do SSOT: nenhuma espera é definida entre a última tentativa e o encerramento por
    # sem_resposta. Padrão 0 = esgota no próximo tick do dispatcher; parametrizável.
    def self.exhaust_grace
      ENV.fetch('UP_SALES_RECOVERY_EXHAUST_GRACE_MINUTES', '0').to_i.minutes
    end

    # §25 `limite_recuperacoes_dia` ("parametrizável/calibrar", sem valor aprovado): vazio = sem teto
    # diário (o pacing por inbox continua sendo o limitador de rajada).
    def self.daily_limit
      value = ENV.fetch('UP_SALES_RECOVERY_DAILY_LIMIT', '').to_s.strip
      value.match?(/\A\d+\z/) ? value.to_i : nil
    end
  end
end
