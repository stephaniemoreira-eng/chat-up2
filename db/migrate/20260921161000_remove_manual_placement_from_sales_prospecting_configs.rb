# A busca automática apenas descobre potenciais leads. A entrada, a etapa e o pipeline são
# definidos pelo Operational Engine; manter uma escolha paralela aqui violaria a direção
# Engine → Sales::* (§3.3/§4).
class RemoveManualPlacementFromSalesProspectingConfigs < ActiveRecord::Migration[7.2]
  def up
    remove_column :sales_prospecting_configs, :sales_stage_id
    remove_column :sales_prospecting_configs, :sales_pipeline_id
  end

  def down
    add_column :sales_prospecting_configs, :sales_pipeline_id, :bigint, null: false
    add_column :sales_prospecting_configs, :sales_stage_id, :bigint
  end
end
