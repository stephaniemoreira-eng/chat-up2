# Fase 5 do SSOT (§8.1, §21.1): o pipeline dedicado do funil Prospect, com as cinco etapas exatas
# do enum `etapa_prospect` -- não o "Comercial" genérico que Sales::Pipelines::SeedDefaultService
# semeia (nem em nome, nem em stages: aquele é New/Qualified/Proposal/Negotiation/Won/Lost, sem
# relação com o funil deste SSOT). `probability` fica de fora de propósito: é um conceito de
# forecast comercial (chance de fechar negócio) sem correspondente definido pra uma etapa de
# qualificação -- inventar um número aqui seria dado de exibição, não de negócio.
class Sales::Pipelines::SeedProspectPipelineService
  ENGINE_KIND = 'prospect'.freeze

  PROSPECT_STAGES = [
    { name: 'Backlog', engine_stage_key: 'backlog', category: :open, color: '#94A3B8' },
    { name: 'Contatado', engine_stage_key: 'contatado', category: :open, color: '#3B82F6' },
    { name: 'Em conversa', engine_stage_key: 'em_conversa', category: :open, color: '#8B5CF6' },
    { name: 'Qualificado', engine_stage_key: 'qualificado', category: :open, color: '#F59E0B' },
    { name: 'Agendado', engine_stage_key: 'agendado', category: :open, color: '#10B981' }
  ].freeze

  LEGACY_STAGE_NAMES = %w[Backlog Contatado Em\ Conversa Qualificado Agendado].freeze

  def initialize(account:)
    @account = account
  end

  def perform
    existing = @account.sales_pipelines.find_by(engine_kind: ENGINE_KIND)
    return existing if existing

    adopt_legacy_pipeline || create_pipeline
  end

  private

  # A primeira versão do Kanban foi criada antes das chaves técnicas. A adoção só ocorre quando
  # a estrutura legada é exatamente a do funil Prospect; não se infere pelo nome livremente
  # editável em instalações desconhecidas.
  def adopt_legacy_pipeline
    pipeline = @account.sales_pipelines.find_by(name: 'Prospecção', engine_kind: nil)
    return unless pipeline

    stages = pipeline.stages.ordered.to_a
    return unless stages.map(&:name) == LEGACY_STAGE_NAMES

    ActiveRecord::Base.transaction do
      pipeline.update!(engine_kind: ENGINE_KIND)
      stages.zip(PROSPECT_STAGES).each { |stage, attributes| stage.update!(engine_stage_key: attributes[:engine_stage_key]) }
    end
    pipeline
  end

  def create_pipeline
    ActiveRecord::Base.transaction do
      pipeline = @account.sales_pipelines.create!(name: 'Prospecção', engine_kind: ENGINE_KIND)
      PROSPECT_STAGES.each { |stage_attrs| pipeline.stages.create!(stage_attrs) }
      pipeline
    end
  end
end
