# Horario com granularidade de hora (0-23) nao bastava pra distribuir muitas contas/segmentos --
# minutos de 5 em 5 dao 288 janelas por dia em vez de 24, tornando mais facil nao empilhar buscas
# no mesmo instante. Nao aumenta o volume de chamadas ao Google Places (continua uma execucao por
# dia por busca), so a precisao de quando ela roda.
class AddScheduledMinuteToSalesProspectingConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_prospecting_configs, :scheduled_minute, :integer, null: false, default: 0
  end
end
