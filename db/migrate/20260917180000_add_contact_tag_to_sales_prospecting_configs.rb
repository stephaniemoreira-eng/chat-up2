# Etiqueta (label do Chatwoot) aplicada automaticamente ao contato quando o lead nasce por esta
# busca -- marca "veio da busca X" de um jeito que tanto o painel quanto o agente de IA enxergam
# (ver CreateLeadsFromResultsService). Null/vazio: nenhuma etiqueta aplicada (comportamento atual).
class AddContactTagToSalesProspectingConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_prospecting_configs, :contact_tag, :string
  end
end
