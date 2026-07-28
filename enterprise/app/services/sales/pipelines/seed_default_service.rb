class Sales::Pipelines::SeedDefaultService
  DEFAULT_STAGES = [
    { name: 'New', category: :open, probability: 10 },
    { name: 'Qualified', category: :open, probability: 25 },
    { name: 'Proposal', category: :open, probability: 50 },
    { name: 'Negotiation', category: :open, probability: 75 },
    { name: 'Won', category: :won, probability: 100 },
    { name: 'Lost', category: :lost, probability: 0 }
  ].freeze

  def initialize(account:)
    @account = account
  end

  def perform
    existing_default = @account.sales_pipelines.find_by(is_default: true)
    return existing_default if existing_default

    ActiveRecord::Base.transaction do
      pipeline = @account.sales_pipelines.create!(name: 'Comercial', is_default: true)
      DEFAULT_STAGES.each { |stage_attrs| pipeline.stages.create!(stage_attrs) }
      pipeline
    end
  end
end
