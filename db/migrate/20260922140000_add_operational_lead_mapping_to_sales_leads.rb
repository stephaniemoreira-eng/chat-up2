# SSOT §5.1/§5.4: liga um Sales::Lead ao lead_id (uuid) que o originou no Operational Engine,
# pra OperationalEngine::SalesProjectionSync casar projeção por fato técnico, não por
# contact_id/pipeline (um contato pode legitimamente ter mais de um card no mesmo pipeline --
# ex.: um card manual criado antes de este lead existir no Engine).
#
# Sem foreign_key: leads vive no Supabase, uma conexão/banco totalmente separado de sales_leads
# (nativo) -- não existe FK entre bancos distintos.
#
# Único por pipeline, não globalmente: o mesmo lead_id aparece em dois Sales::Lead quando o
# Engine tem oportunidade tanto em Prospecção quanto em Comercial (dois pipelines, dois cards).
class AddOperationalLeadMappingToSalesLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_leads, :operational_lead_id, :uuid

    add_index :sales_leads, %i[sales_pipeline_id operational_lead_id],
               unique: true,
               where: 'operational_lead_id IS NOT NULL',
               name: 'index_sales_leads_on_pipeline_and_operational_lead_id'
  end
end
