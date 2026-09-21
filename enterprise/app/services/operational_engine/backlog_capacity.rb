# Capacidade de novas ativações do §10.4 e §25: quantos leads novos ainda podem ser abordados
# agora, respeitando dia útil, janela do horário atual e os dois tetos (por janela e diário).
# "20 é teto, não obrigação" e "não compensar janela perdida com blast posterior" -- por isso o
# cálculo é sempre relativo a AGORA, nunca tenta recuperar capacidade não usada de uma janela
# que já fechou.
#
# Parâmetros hardcoded aqui de propósito, não espalhados pelo dispatcher (Fase 6, ainda não
# escrito): "centralizados/configuráveis, não duplicados em prompt ou múltiplos arquivos" (§25)
# significa UMA fonte, não necessariamente já uma tabela editável -- só existe um cliente
# operacional (Lava e Pronto) hoje. `conta_id` já entra na assinatura pra não forçar reescrever
# todo chamador quando isso virar configuração por conta de verdade.
module OperationalEngine
  class BacklogCapacity
    TIMEZONE = 'America/Sao_Paulo'
    LIMITE_DIA = 20
    JANELAS = [
      { inicio_min: 9 * 60, fim_min: 11 * 60, limite: 10 },  # 09:00-11:00
      { inicio_min: 14 * 60, fim_min: 16 * 60, limite: 10 }  # 14:00-16:00
    ].freeze
    DIAS_OPERACIONAIS = (1..5) # Date#wday: 0=domingo..6=sábado

    def self.disponivel(conta_id:, agora: Time.current)
      new(conta_id: conta_id, agora: agora).disponivel
    end

    def initialize(conta_id:, agora: Time.current)
      @conta_id = conta_id
      # Timezone explícito, não confia no Time.zone global do processo (que aqui é UTC por
      # padrão) -- horário de negócio é sempre América/São Paulo, deploy ou timezone da máquina
      # não devem poder mudar em que hora o dispatcher liga.
      @agora = agora.in_time_zone(TIMEZONE)
    end

    def disponivel
      return 0 unless dia_operacional?

      janela = janela_atual
      return 0 if janela.nil?

      [restante_na_janela(janela), restante_no_dia].min
    end

    private

    def dia_operacional?
      DIAS_OPERACIONAIS.cover?(@agora.wday)
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

    # §10.6: primeiro_contato_em só é gravado quando o provedor confirma envio real -- essa é a
    # definição operacional de "ativação", não a criação do lead nem uma tentativa qualquer.
    def ativados_entre(inicio, fim)
      OperationalEngine::Lead.where(conta_id: @conta_id, primeiro_contato_em: inicio..fim).count
    end
  end
end
