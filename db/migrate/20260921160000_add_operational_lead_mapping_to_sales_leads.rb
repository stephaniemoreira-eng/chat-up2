# A referência é técnica: Sales::Lead continua sendo somente uma projeção do estado que vive no
# Operational Engine. Um mesmo lead pode ter uma projeção no pipeline Prospect e outra no
# Comercial, mas nunca dois cards no mesmo pipeline (§5.2/§8.4).
class AddOperationalLeadMappingToSalesLeads < ActiveRecord::Migration[7.2]
  def change
    add_column :sales_leads, :operational_lead_id, :uuid
    add_index :sales_leads, %i[account_id sales_pipeline_id operational_lead_id],
              unique: true,
              where: 'operational_lead_id IS NOT NULL',
              name: 'index_sales_leads_on_engine_projection'
  end
end
