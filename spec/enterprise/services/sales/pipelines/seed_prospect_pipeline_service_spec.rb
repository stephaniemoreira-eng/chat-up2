require 'rails_helper'

RSpec.describe Sales::Pipelines::SeedProspectPipelineService do
  let(:account) { create(:account) }

  describe '#perform' do
    it 'creates a pipeline marked engine_kind prospect, named Prospecção' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline.engine_kind).to eq('prospect')
      expect(pipeline.name).to eq('Prospecção')
      expect(pipeline.account).to eq(account)
    end

    it 'creates the five SSOT stages in order, each with its engine_stage_key (§8.1)' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline.stages.ordered.pluck(:name)).to eq(['Backlog', 'Contatado', 'Em conversa', 'Qualificado', 'Agendado'])
      expect(pipeline.stages.ordered.pluck(:engine_stage_key)).to eq(%w[backlog contatado em_conversa qualificado agendado])
    end

    it 'does not mark any stage won/lost -- that is a Comercial board concept (Fase 9), not Prospect' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline.stages.pluck(:category).uniq).to eq(['open'])
    end

    it 'is idempotent when a prospect pipeline already exists' do
      existing = create(:sales_pipeline, account: account, engine_kind: 'prospect')

      expect { described_class.new(account: account).perform }.not_to change(Sales::Pipeline, :count)
      expect(described_class.new(account: account).perform).to eq(existing)
    end

    it 'does not create stages when returning an existing prospect pipeline' do
      create(:sales_pipeline, account: account, engine_kind: 'prospect')

      expect { described_class.new(account: account).perform }.not_to change(Sales::Stage, :count)
    end

    it 'does not collide with the generic default (Comercial) pipeline' do
      default_pipeline = Sales::Pipelines::SeedDefaultService.new(account: account).perform
      prospect_pipeline = described_class.new(account: account).perform

      expect(prospect_pipeline).not_to eq(default_pipeline)
      expect(account.sales_pipelines.count).to eq(2)
    end
  end
end
