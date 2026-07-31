class AddSummaryToSalesLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_leads, :summary, :text
  end
end
