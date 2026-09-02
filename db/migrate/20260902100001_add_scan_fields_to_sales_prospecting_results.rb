class AddScanFieldsToSalesProspectingResults < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_prospecting_results, :scan_status, :string, default: 'pendente', null: false
    add_column :sales_prospecting_results, :scan_versao, :string, default: 'v1', null: false
    add_column :sales_prospecting_results, :scan_score, :integer
    add_column :sales_prospecting_results, :scan_faixa, :string
    add_column :sales_prospecting_results, :scan_pilares, :jsonb, default: {}, null: false
    add_column :sales_prospecting_results, :scan_evidencias, :jsonb, default: {}, null: false
    add_column :sales_prospecting_results, :scan_aprovado, :boolean, default: false, null: false
    add_column :sales_prospecting_results, :scan_liberado_envio, :boolean, default: false, null: false
    add_column :sales_prospecting_results, :scanned_at, :datetime

    add_index :sales_prospecting_results, :scan_status
  end
end
