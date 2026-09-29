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
