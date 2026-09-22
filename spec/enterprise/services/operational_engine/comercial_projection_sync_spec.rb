require 'rails_helper'

RSpec.describe OperationalEngine::ComercialProjectionSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id
    }.merge(overrides))
  end

  it 'nao faz nada quando o lead nao tem upsales_contact_id ainda' do
    lead = build_lead(upsales_contact_id: nil, etapa_comercial: 'oportunidade')

    expect(described_class.call(lead)).to be_nil
    expect(Sales::Lead.count).to eq(0)
  end

  it 'nao faz nada quando ainda nao existe oportunidade (etapa_comercial nulo, §8.4)' do
    lead = build_lead(etapa_comercial: nil)

    expect(described_class.call(lead)).to be_nil
    expect(Sales::Lead.count).to eq(0)
  end

  describe 'quando etapa_comercial esta preenchido' do
    it 'cria o card no pipeline Oportunidades, na stage correspondente' do
      lead = build_lead(etapa_comercial: 'oportunidade', empresa: 'Lava e Pronto')

      sales_lead = described_class.call(lead)

      expect(sales_lead).to be_persisted
      expect(sales_lead.pipeline.engine_kind).to eq('comercial')
      expect(sales_lead.pipeline.name).to eq('Oportunidades')
      expect(sales_lead.stage.engine_stage_key).to eq('oportunidade')
      expect(sales_lead.title).to eq('Lava e Pronto')
    end

    it 'atualiza o card existente em vez de duplicar' do
      lead = build_lead(etapa_comercial: 'oportunidade', empresa: 'Nome Antigo')
      described_class.call(lead)

      lead.update!(empresa: 'Nome Novo')
      described_class.call(lead)

      expect(Sales::Lead.where(contact_id: contact.id).count).to eq(1)
      expect(Sales::Lead.find_by(contact_id: contact.id).title).to eq('Nome Novo')
    end

    it 'move o card quando etapa_comercial avanca' do
      lead = build_lead(etapa_comercial: 'oportunidade')
      described_class.call(lead)

      lead.update!(etapa_comercial: 'em_acompanhamento')
      sales_lead = described_class.call(lead)

      expect(sales_lead.stage.engine_stage_key).to eq('em_acompanhamento')
    end

    it 'chega ate Ganho/Perdido (permitido porque e o sistema, nao um drag humano -- §17.4)' do
      lead = build_lead(etapa_comercial: 'ganho')

      sales_lead = described_class.call(lead)

      expect(sales_lead.stage.engine_stage_key).to eq('ganho')
      expect(sales_lead).to be_won
      expect(sales_lead.closed_at).to be_present
    end

    it 'move um card JA EXISTENTE ate Ganho via MoveStageService (nao so na criacao) -- §17.4/§21.2' do
      lead = build_lead(etapa_comercial: 'oportunidade')
      described_class.call(lead)

      lead.update!(etapa_comercial: 'ganho')
      sales_lead = described_class.call(lead)

      expect(sales_lead.reload.stage.engine_stage_key).to eq('ganho')
      expect(sales_lead).to be_won
    end

    it 'nasce com status/closed_at corretos mesmo na primeira sincronizacao ja em Perdido' do
      lead = build_lead(etapa_comercial: 'perdido')

      sales_lead = described_class.call(lead)

      expect(sales_lead).to be_lost
      expect(sales_lead.closed_at).to be_present
    end

    it 'nasce aberto (sem closed_at) quando a etapa e uma etapa aberta' do
      lead = build_lead(etapa_comercial: 'oportunidade')

      sales_lead = described_class.call(lead)

      expect(sales_lead).to be_open
      expect(sales_lead.closed_at).to be_nil
    end

    it 'registra a transicao com user nil (sistema)' do
      lead = build_lead(etapa_comercial: 'oportunidade')
      sales_lead = described_class.call(lead)

      lead.update!(etapa_comercial: 'perdido')
      described_class.call(lead)

      transition = sales_lead.stage_transitions.first
      expect(transition.to_stage.engine_stage_key).to eq('perdido')
      expect(transition.user).to be_nil
    end

    it 'nao mexe no card que o mesmo contato tem no pipeline Prospeccao' do
      prospect_lead = build_lead(etapa_prospect: 'qualificado')
      OperationalEngine::SalesProjectionSync.call(prospect_lead)
      prospect_card = Sales::Lead.find_by(contact_id: contact.id)

      comercial_lead = OperationalEngine::Lead.find(prospect_lead.lead_id)
      comercial_lead.update!(etapa_comercial: 'oportunidade')
      described_class.call(comercial_lead)

      expect(prospect_card.reload.pipeline.engine_kind).to eq('prospect')
      expect(Sales::Lead.where(contact_id: contact.id).count).to eq(2)
    end
  end

  describe 'casamento por operational_lead_id, nao so contact_id+pipeline' do
    it 'grava operational_lead_id na criacao' do
      lead = build_lead(etapa_comercial: 'oportunidade')

      sales_lead = described_class.call(lead)

      expect(sales_lead.operational_lead_id).to eq(lead.lead_id)
      expect(sales_lead.source).to eq('operational_engine')
    end

    it 'adota um card legado (sem operational_lead_id) quando ha exatamente um candidato no pipeline' do
      comercial_pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
      oportunidade_stage = comercial_pipeline.stages.find_by!(engine_stage_key: 'oportunidade')
      legacy_card = create(:sales_lead, account: account, contact: contact, pipeline: comercial_pipeline,
                                         stage: oportunidade_stage, title: 'Card de antes do operational_lead_id existir')
      lead = build_lead(etapa_comercial: 'em_acompanhamento')

      sales_lead = described_class.call(lead)

      expect(sales_lead.id).to eq(legacy_card.id)
      expect(sales_lead.reload.operational_lead_id).to eq(lead.lead_id)
    end

    it 'recusa adivinhar (levanta ProjectionIntegrityError) quando ha MAIS de um card legado ambiguo no pipeline' do
      comercial_pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
      oportunidade_stage = comercial_pipeline.stages.find_by!(engine_stage_key: 'oportunidade')
      create(:sales_lead, account: account, contact: contact, pipeline: comercial_pipeline, stage: oportunidade_stage, title: 'Card A')
      create(:sales_lead, account: account, contact: contact, pipeline: comercial_pipeline, stage: oportunidade_stage, title: 'Card B')
      lead = build_lead(etapa_comercial: 'oportunidade')

      expect { described_class.call(lead) }.to raise_error(OperationalEngine::ComercialProjectionSync::ProjectionIntegrityError)
    end

    it 'nao adota de novo um card que ja tem operational_lead_id de OUTRO lead' do
      other_lead = build_lead(etapa_comercial: 'oportunidade')
      described_class.call(other_lead)

      lead = build_lead(etapa_comercial: 'oportunidade')

      sales_lead = described_class.call(lead)

      expect(sales_lead.operational_lead_id).to eq(lead.lead_id)
      expect(Sales::Lead.where(contact_id: contact.id).count).to eq(2)
    end
  end

  describe 'tags computadas (§20.2, §20.3)' do
    it 'nao mostra tag pra propensao nao_classificado' do
      lead = build_lead(etapa_comercial: 'oportunidade', propensao_fechamento: 'nao_classificado')

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to eq([])
    end

    it 'mostra a tag da propensao quando classificada' do
      lead = build_lead(etapa_comercial: 'oportunidade', propensao_fechamento: 'quente')

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to eq(['quente'])
    end

    it 'adiciona callback quando agendamento_status e callback_registrado (§16.2)' do
      lead = build_lead(etapa_comercial: 'oportunidade', agendamento_status: 'callback_registrado')

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to include('callback')
    end

    it 'adiciona no_show quando no_show_em esta preenchido, sem mudar a etapa (§20.3)' do
      lead = build_lead(etapa_comercial: 'em_acompanhamento', no_show_em: Time.current)

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to include('no_show')
      expect(sales_lead.stage.engine_stage_key).to eq('em_acompanhamento')
    end

    it 'tira a tag no_show quando o campo volta a nulo (tratado/remarcado)' do
      lead = build_lead(etapa_comercial: 'oportunidade', no_show_em: Time.current)
      described_class.call(lead)

      lead.update!(no_show_em: nil)
      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).not_to include('no_show')
    end
  end
end
