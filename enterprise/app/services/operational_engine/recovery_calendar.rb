# CP-13 (P1-VAL-12; SSOT §15.3, §15.4, §15.5, §25): a aritmética de tempo do Recovery -- "dia útil",
# "+2h", "+3 dias" e a janela de recovery (segunda a sexta, 09:00-18:00, America/Sao_Paulo).
#
# "Janela = elegibilidade, não obrigação de enviar exatamente no timestamp" (§15.5): o offset da
# cadência dá o horário mínimo; se ele cair fora da janela, carrega para o próximo instante útil
# (§15.4 "se cair fora da janela, carregar para a próxima janela útil").
#
# Dia útil = segunda a sexta. LACUNA registrada: o SSOT não traz calendário de feriados, então
# feriado conta como dia útil até existir uma fonte oficial (mudança de parâmetro, não de motor).
#
# Timezone explícito (mesmo motivo do BacklogCapacity): o Time.zone do processo é UTC por padrão.
module OperationalEngine
  class RecoveryCalendar
    TIMEZONE = 'America/Sao_Paulo'.freeze
    DIAS_UTEIS = (1..5) # Date#wday: 0=domingo..6=sábado
    OFFSET = /\A([1-9]\d*)(h|d|bd)\z/

    # TEST-WINDOW-01: a mesma exceção temporária de homologação da primeira abordagem.
    # Ela só vale em dias úteis e expira fechada; fora dela, a janela do SSOT permanece intacta.
    TEST_OVERRIDE_ENABLED_ENV = 'OPERATIONAL_ENGINE_TEST_OVERRIDE_ENABLED'
    TEST_OVERRIDE_MODE_ENV = 'OPERATIONAL_ENGINE_TEST_WINDOW_OVERRIDE'
    TEST_OVERRIDE_UNTIL_ENV = 'OPERATIONAL_ENGINE_TEST_WINDOW_OVERRIDE_UNTIL'
    TEST_OVERRIDE_FULL_DAY = 'full_day'

    class InvalidOffset < ArgumentError; end

    # §25 janela_recuperacao_inicio/fim -- configuração operacional, padrão = SSOT.
    def self.window_start_min
      parse_hhmm(ENV.fetch('UP_SALES_RECOVERY_WINDOW_START', '09:00'), 9 * 60)
    end

    def self.window_end_min
      parse_hhmm(ENV.fetch('UP_SALES_RECOVERY_WINDOW_END', '18:00'), 18 * 60)
    end

    def self.within_window?(time)
      local = time.in_time_zone(TIMEZONE)
      return true if test_window_override_active?(local)

      DIAS_UTEIS.cover?(local.wday) && minute_of_day(local) >= window_start_min && minute_of_day(local) < window_end_min
    end

    # O primeiro instante >= time dentro da janela.
    def self.next_window_at(time)
      local = time.in_time_zone(TIMEZONE)
      8.times do
        return local if within_window?(local)
        return at_minute(local, window_start_min) if DIAS_UTEIS.cover?(local.wday) && minute_of_day(local) < window_start_min

        local = at_minute(local + 1.day, window_start_min)
      end
      local
    end

    # Aplica um offset de cadência ("2h", "3d", "1bd") a partir do baseline -- sem janela (ver
    # next_window_at). bd = dia útil: avança dia a dia pulando sábado/domingo, mantendo a hora.
    def self.shift(baseline, token)
      match = OFFSET.match(token.to_s.strip)
      raise InvalidOffset, "offset inválido: #{token.inspect}" if match.nil?

      amount = match[1].to_i
      case match[2]
      when 'h' then baseline + amount.hours
      when 'd' then baseline + amount.days
      else add_business_days(baseline, amount)
      end
    end

    def self.valid_offset?(token)
      OFFSET.match?(token.to_s.strip)
    end

    def self.add_business_days(time, days)
      local = time.in_time_zone(TIMEZONE)
      days.times do
        local += 1.day
        local += 1.day until DIAS_UTEIS.cover?(local.wday)
      end
      local
    end

    def self.test_window_override_active?(local)
      return false unless DIAS_UTEIS.cover?(local.wday)
      return false unless ENV[TEST_OVERRIDE_ENABLED_ENV] == 'true'
      return false unless ENV[TEST_OVERRIDE_MODE_ENV] == TEST_OVERRIDE_FULL_DAY

      Time.iso8601(ENV.fetch(TEST_OVERRIDE_UNTIL_ENV)).in_time_zone(TIMEZONE) >= local
    rescue ArgumentError, KeyError, TypeError
      false
    end

    def self.minute_of_day(local)
      (local.hour * 60) + local.min
    end

    def self.at_minute(local, minutes)
      local.change(hour: minutes / 60, min: minutes % 60, sec: 0)
    end

    def self.parse_hhmm(value, fallback)
      match = /\A(\d{1,2}):(\d{2})\z/.match(value.to_s.strip)
      return fallback if match.nil?

      (match[1].to_i * 60) + match[2].to_i
    end
    private_class_method :minute_of_day, :at_minute, :parse_hhmm
  end
end
