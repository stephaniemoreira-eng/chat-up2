require 'rails_helper'

RSpec.describe Sales::Pipelines::SeedComercialPipelineService do
  let(:account) { create(:account) }

  describe '#perform' do
    it 'creates a pipeline marked engine_kind comercial, named Oportunidades' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline.engine_kind).to eq('comercial')
      expect(pipeline.name).to eq('Oportunidades')
      expect(pipeline.account).to eq(account)
    end

    it 'creates the four SSOT stages in order, each with its engine_stage_key (§8.4)' do
      pipeline = described_class.new(account: account).perform

      expect(pipeline.stages.ordered.pluck(:name)).to eq(['Oportunidade', 'Em acompanhamento', 'Ganho', 'Perdido'])
      expect(pipeline.stages.ordered.pluck(:engine_stage_key)).to eq(%w[oportunidade em_acompanhamento ganho perdido])
    end

    it 'marks Ganho won and Perdido lost, so MoveStageService derives status on its own' do
      pipeline = described_class.new(account: account).perform
      stages_by_key = pipeline.stages.index_by(&:engine_stage_key)

      expect(stages_by_key['oportunidade']).to be_open
      expect(stages_by_key['em_acompanhamento']).to be_open
      expect(stages_by_key['ganho']).to be_won
      expect(stages_by_key['perdido']).to be_lost
    end

    it 'is idempotent when a comercial pipeline already exists' do
      existing = create(:sales_pipeline, account: account, engine_kind: 'comercial')

      expect { described_class.new(account: account).perform }.not_to change(Sales::Pipeline, :count)
      expect(described_class.new(account: account).perform).to eq(existing)
    end

    it 'does not collide with the Prospecção pipeline nor the generic default (Comercial) pipeline' do
      default_pipeline = Sales::Pipelines::SeedDefaultService.new(account: account).perform
      prospect_pipeline = Sales::Pipelines::SeedProspectPipelineService.new(account: account).perform
      comercial_pipeline = described_class.new(account: account).perform

      expect([default_pipeline, prospect_pipeline, comercial_pipeline].uniq.size).to eq(3)
      expect(account.sales_pipelines.count).to eq(3)
    end
  end
end
