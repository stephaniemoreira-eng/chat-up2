# Trava por busca: decide se os leads criados por essa busca automatica podem ser contatados
# ativamente pelo agente de IA assim que entram no Kanban, ou se ficam aguardando liberacao manual.
# Default false -- contato automatico e opt-in por busca, nunca ligado sozinho.
class AddAutoContactEnabledToSalesProspectingConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_prospecting_configs, :auto_contact_enabled, :boolean, null: false, default: false
  end
end
