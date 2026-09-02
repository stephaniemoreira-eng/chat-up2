# == Schema Information
#
# Table name: sales_prospecting_results
#
#  id                          :bigint           not null, primary key
#  address                     :string
#  name                        :string
#  phone_number                :string
#  place_id                    :string           not null
#  rating                      :decimal(2, 1)
#  scan_aprovado               :boolean          default(false), not null
#  scan_evidencias             :jsonb            not null
#  scan_faixa                  :string
#  scan_liberado_envio         :boolean          default(false), not null
#  scan_pilares                :jsonb            not null
#  scan_score                  :integer
#  scan_status                 :string           default("pendente"), not null
#  scan_versao                 :string           default("v1"), not null
#  scanned_at                  :datetime
#  user_ratings_total          :integer
#  website                     :string
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  sales_lead_id               :bigint
#  sales_prospecting_search_id :bigint           not null
#
# Indexes
#
#  index_sales_prospecting_results_on_account_id  (account_id)
#  index_sales_prospecting_results_on_place_id    (place_id)
#  index_sales_prospecting_results_on_scan_status (scan_status)
#  index_sales_prospecting_results_on_search_id   (sales_prospecting_search_id)
#
class Sales::ProspectingResult < ApplicationRecord
  self.table_name = 'sales_prospecting_results'

  # Faixas do SCAN v1 (ver UP2_SCAN_Arquitetura_Pre_Diagnostico_v1.docx, secao 10):
  # 0-49 baixa_prioridade, 50-69 revisao_humana, 70-100 revisao_prioritaria.
  enum scan_status: { pendente: 'pendente', concluido: 'concluido', erro: 'erro' }, _prefix: :scan

  belongs_to :account
  belongs_to :search, class_name: 'Sales::ProspectingSearch', foreign_key: :sales_prospecting_search_id, inverse_of: :results
  belongs_to :lead, class_name: 'Sales::Lead', foreign_key: :sales_lead_id, optional: true

  validates :place_id, presence: true
end
