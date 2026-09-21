# Fase 9 do SSOT (§8.4, §21.3): o pipeline dedicado do funil Comercial, com as quatro etapas
# exatas do enum `etapa_comercial`. Nome "Oportunidades", não "Comercial", de propósito -- já
# existe um pipeline "Comercial" genérico (Sales::Pipelines::SeedDefaultService, sem relação
# nenhuma com o Engine) e ter dois pipelines com o mesmo nome no seletor confundiria mais do que
# ajudaria. `category` aqui não é decorativo: Ganho/Perdido usam won/lost de propósito, pra
# Sales::Leads::MoveStageService derivar status/closed_at sozinho (mesmo mecanismo que o pipeline
# "Comercial" genérico já usa).
class Sales::Pipelines::SeedComercialPipelineService
  ENGINE_KIND = 'comercial'.freeze

  COMERCIAL_STAGES = [
    { name: 'Oportunidade', engine_stage_key: 'oportunidade', category: :open, color: '#3B82F6' },
    { name: 'Em acompanhamento', engine_stage_key: 'em_acompanhamento', category: :open, color: '#F59E0B' },
    { name: 'Ganho', engine_stage_key: 'ganho', category: :won, color: '#10B981' },
    { name: 'Perdido', engine_stage_key: 'perdido', category: :lost, color: '#94A3B8' }
  ].freeze

  def initialize(account:)
    @account = account
  end

  def perform
    existing = @account.sales_pipelines.find_by(engine_kind: ENGINE_KIND)
    return existing if existing

    ActiveRecord::Base.transaction do
      pipeline = @account.sales_pipelines.create!(name: 'Oportunidades', engine_kind: ENGINE_KIND)
      COMERCIAL_STAGES.each { |stage_attrs| pipeline.stages.create!(stage_attrs) }
      pipeline
    end
  end
end
