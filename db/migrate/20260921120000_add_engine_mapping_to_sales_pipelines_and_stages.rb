# Fase 5 do SSOT (§8.1, §21.1): a Kanban Prospect precisa de um pipeline dedicado, com stages que
# correspondem 1:1 ao enum `etapa_prospect` do Operational Engine (backlog/contatado/em_conversa/
# qualificado/agendado) -- não o pipeline "Comercial" genérico que Sales::Pipelines::
# SeedDefaultService já semeia pra outros usos.
#
# `name`/`position` são editáveis por qualquer usuário na UI (StageDialog.vue), então não servem
# de chave estável pra sincronização -- um usuário podia renomear "Backlog" e quebrar o mapeamento
# em silêncio. `engine_kind`/`engine_stage_key` existem só pra isso: nunca aparecem na UI, só o
# seed service (Sales::Pipelines::SeedProspectPipelineService) os grava.
class AddEngineMappingToSalesPipelinesAndStages < ActiveRecord::Migration[7.2]
  def change
    add_column :sales_pipelines, :engine_kind, :string
    add_index :sales_pipelines, %i[account_id engine_kind], unique: true,
                                                              where: 'engine_kind IS NOT NULL',
                                                              name: 'index_sales_pipelines_on_account_id_and_engine_kind'

    add_column :sales_stages, :engine_stage_key, :string
    add_index :sales_stages, %i[sales_pipeline_id engine_stage_key], unique: true,
                                                                      where: 'engine_stage_key IS NOT NULL',
                                                                      name: 'index_sales_stages_on_pipeline_id_and_engine_stage_key'
  end
end
