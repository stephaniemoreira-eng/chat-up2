# == Schema Information
#
# Table name: sales_prospecting_configs
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  auto_contact_enabled :boolean       default(FALSE), not null
#  business_type     :string           not null
#  city              :string           not null
#  desired_count     :integer          default(20), not null
#  exclude_keywords  :string
#  last_run_at       :datetime
#  min_rating        :decimal(2, 1)
#  min_reviews       :integer
#  neighborhood      :string
#  require_phone     :boolean          default(FALSE), not null
#  require_website   :boolean          default(FALSE), not null
#  scheduled_hour    :integer          default(6), not null
#  state             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  sales_pipeline_id :bigint           not null
#  sales_stage_id    :bigint
#
# Indexes
#
#  index_sales_prospecting_configs_on_account_id             (account_id)
#  index_sales_prospecting_configs_on_account_id_and_active  (account_id,active)
#
# Uma busca salva (segmento + localizacao + filtros), executada sozinha todo dia pelo
# Sales::Prospecting::AutoSearchJob -- em vez de alguem abrir o formulario manual da tela de
# Busca/Prospeccao toda vez. Ver docs/fork (12-saas-prospeccao-multicliente.md, item 1) e
# Sales::Prospecting::RunConfigService.
#
# scheduled_hour (0-23, UTC): cada config roda no seu proprio horario -- o AutoSearchJob agora
# roda a cada hora e filtra pelas configs daquela hora, em vez de todo mundo no mesmo 06:00 fixo.
# Existe pra nao concentrar todas as contas/clientes batendo a API do Google Places juntas.
#
# auto_contact_enabled: trava por busca -- decide se os leads criados por ela podem ser
# contatados ativamente pelo agente de IA assim que entram no Kanban (feature ainda em
# construcao) ou se ficam aguardando liberacao manual. Default false: contato automatico e
# opt-in, nunca ligado sozinho so por a busca existir. Gravado em Sales::Lead#additional_attributes
# no momento da criacao (ver CreateLeadsFromResultsService) pra sobreviver a mudanca posterior
# na config.
class Sales::ProspectingConfig < ApplicationRecord
  self.table_name = 'sales_prospecting_configs'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Sales::Pipeline', foreign_key: :sales_pipeline_id, inverse_of: false
  belongs_to :stage, class_name: 'Sales::Stage', foreign_key: :sales_stage_id, optional: true, inverse_of: false

  validates :business_type, :city, :state, presence: true
  validates :scheduled_hour, inclusion: { in: 0..23 }

  scope :active, -> { where(active: true) }
end
