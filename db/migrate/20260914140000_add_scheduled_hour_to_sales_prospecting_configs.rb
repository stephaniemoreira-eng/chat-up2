# Uma busca por conta ja rodava toda no mesmo horario fixo (06:00 UTC, ver AutoSearchJob) --
# com varias contas/clientes isso significa todo mundo batendo a API do Google Places ao mesmo
# tempo. Deixa cada config escolher sua propria hora do dia (0-23, UTC) pra distribuir a carga.
class AddScheduledHourToSalesProspectingConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_prospecting_configs, :scheduled_hour, :integer, null: false, default: 6
  end
end
