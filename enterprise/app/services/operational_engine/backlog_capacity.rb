# Capacidade de novas ativações do §10.4 e §25: quantos leads novos ainda podem ser abordados
# agora, respeitando dia útil, janela do horário atual e os dois tetos (por janela e diário).
# "20 é teto, não obrigação" e "não compensar janela perdida com blast posterior" -- por isso o
# cálculo é sempre relativo a AGORA, nunca tenta recuperar capacidade não usada de uma janela
# que já fechou.
#
# Parâmetros centralizados nesta fonte: ainda existe somente um cliente operacional, mas conta_id
# já faz parte da assinatura para permitir configuração por conta no futuro.
module OperationalEngine
  class BacklogCapacity
    TIMEZONE = 'America/Sao_Paulo'
    LIMITE_DIA = 20
    JANELAS = [
      { inicio_min: 9 * 60, fim_min: 11 * 60, limite: 10 },  # 09:00-11:00
      { inicio_min: 14 * 60, fim_min: 17 * 60, limite: 10 }  # 14:00-17:00
    ].freeze
    DIAS_OPERACIONAIS = (1..5) # Date#wday: 0=domingo..6=sábado

    # TEST-WINDOW-01: exceção temporária de homologação. O comportamento padrão continua sendo
    # o SSOT; a exceção só é habilitada por três variáveis e expira de forma fechada.
    TEST_OVERRIDE_ENABLED_ENV = 'OPERATIONAL_ENGINE_TEST_OVERRIDE_ENABLED'
    TEST_OVERRIDE_MODE_ENV = 'OPERATIONAL_ENGINE_TEST_WINDOW_OVERRIDE'
    TEST_OVERRIDE_UNTIL_ENV = 'OPERATIONAL_ENGINE_TEST_WINDOW_OVERRIDE_UNTIL'
    TEST_OVERRIDE_FULL_DAY = 'full_day'

    def self.disponivel(conta_id:, agora: Time.current)
      new(conta_id: conta_id, agora: agora).disponivel
    end

    def initialize(conta_id:, agora: Time.current)
      @conta_id = conta_id
      # Horário de negócio é sempre América/São Paulo, independente do timezone do processo.
      @agora = agora.in_time_zone(TIMEZONE)
    end

    def disponivel
      return 0 unless dia_operacional?
      return restante_no_dia if test_window_override_active?

      janela = janela_atual
      return 0 if janela.nil?

      [restante_na_janela(janela), restante_no_dia].min
    end

    private

    def dia_operacional?
      DIAS_OPERACIONAIS.cover?(@agora.wday)
    end

    def test_window_override_active?
      return false unless ENV[TEST_OVERRIDE_ENABLED_ENV] == 'true'
      return false unless ENV[TEST_OVERRIDE_MODE_ENV] == TEST_OVERRIDE_FULL_DAY

      Time.iso8601(ENV.fetch(TEST_OVERRIDE_UNTIL_ENV)).in_time_zone(TIMEZONE) >= @agora
    rescue ArgumentError, KeyError, TypeError
      false
    end

    def janela_atual
      JANELAS.find { |j| minuto_do_dia.between?(j[:inicio_min], j[:fim_min]) }
    end

    def minuto_do_dia
      @agora.hour * 60 + @agora.min
    end

    def restante_na_janela(janela)
      inicio = horario(janela[:inicio_min])
      fim = horario(janela[:fim_min])
      [janela[:limite] - ativados_entre(inicio, fim), 0].max
    end

    def restante_no_dia
      [LIMITE_DIA - ativados_entre(@agora.beginning_of_day, @agora.end_of_day), 0].max
    end

    def horario(minutos_desde_meia_noite)
      @agora.change(hour: minutos_desde_meia_noite / 60, min: minutos_desde_meia_noite % 60, sec: 0)
    end

    def ativados_entre(inicio, fim)
      OperationalEngine::Lead.where(conta_id: @conta_id, primeiro_contato_em: inicio..fim).count
    end
  end
end
