require 'rails_helper'

RSpec.describe OperationalEngine::SalesProjectionSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      etapa_prospect: 'backlog'
    }.merge(overrides))
  end

  it 'nao faz nada quando o lead nao tem upsales_contact_id ainda' do
    lead = build_lead(upsales_contact_id: nil)

    expect(described_class.call(lead)).to be_nil
    expect(Sales::Lead.count).to eq(0)
  end

  it 'cria um Sales::Lead pro contato quando ainda nao existe um' do
    lead = build_lead(empresa: 'Lava e Pronto')

    sales_lead = described_class.call(lead)

    expect(sales_lead).to be_persisted
    expect(sales_lead.account_id).to eq(account.id)
    expect(sales_lead.contact_id).to eq(contact.id)
    expect(sales_lead.title).to eq('Lava e Pronto')
  end

  it 'atualiza o Sales::Lead existente em vez de duplicar' do
    lead = build_lead(empresa: 'Nome Antigo')
    described_class.call(lead)

    lead.update!(empresa: 'Nome Novo')
    described_class.call(lead)

    expect(Sales::Lead.where(contact_id: contact.id).count).to eq(1)
    expect(Sales::Lead.find_by(contact_id: contact.id).title).to eq('Nome Novo')
  end

  it 'usa o nome quando nao ha empresa, e o telefone como ultimo recurso' do
    lead = build_lead(empresa: nil, nome: 'Fulano')
    expect(described_class.call(lead).title).to eq('Fulano')

    other_contact = create(:contact, account: account)
    lead_sem_nome = build_lead(empresa: nil, nome: nil, upsales_contact_id: other_contact.id)
    expect(described_class.call(lead_sem_nome).title).to eq(lead_sem_nome.telefone)
  end

  describe 'pipeline e stage dedicados (Fase 5, §8.1)' do
    it 'cria o card no pipeline Prospecção, nao no Comercial generico' do
      lead = build_lead

      sales_lead = described_class.call(lead)

      expect(sales_lead.pipeline.engine_kind).to eq('prospect')
      expect(sales_lead.pipeline.name).to eq('Prospecção')
    end

    it 'coloca o card na stage que corresponde ao etapa_prospect atual' do
      lead = build_lead(etapa_prospect: 'qualificado')

      sales_lead = described_class.call(lead)

      expect(sales_lead.stage.engine_stage_key).to eq('qualificado')
    end

    it 'move o card quando etapa_prospect muda entre sincronizacoes' do
      lead = build_lead(etapa_prospect: 'backlog')
      sales_lead = described_class.call(lead)
      expect(sales_lead.stage.engine_stage_key).to eq('backlog')

      lead.update!(etapa_prospect: 'em_conversa')
      sales_lead = described_class.call(lead)

      expect(sales_lead.reload.stage.engine_stage_key).to eq('em_conversa')
    end

    it 'registra a transicao (Sales::StageTransition) quando o card muda de etapa, com user nil (sistema)' do
      lead = build_lead(etapa_prospect: 'backlog')
      sales_lead = described_class.call(lead)

      lead.update!(etapa_prospect: 'contatado')
      described_class.call(lead)

      transition = sales_lead.stage_transitions.first
      expect(transition.to_stage.engine_stage_key).to eq('contatado')
      expect(transition.user).to be_nil
    end

    it 'sincroniza ate Agendado apenas quando o Calendar confirmou uma reuniao real' do
      lead = build_lead(
        etapa_prospect: 'agendado', agendamento_status: 'confirmado',
        calendar_event_id: 'calendar-evt-1', agendado_em: Time.current
      )

      sales_lead = described_class.call(lead)

      expect(sales_lead.stage.engine_stage_key).to eq('agendado')
    end

    it 'nao aceita projetar Agendado sem confirmacao real do Calendar' do
      expect do
        build_lead(etapa_prospect: 'agendado')
      end.to raise_error(ActiveRecord::RecordInvalid, /confirmed Calendar event/)
    end

    it 'nao mexe num Sales::Lead que o contato tem em OUTRO pipeline (ex.: importado pela tela de busca)' do
      other_pipeline = create(:sales_pipeline, account: account)
      manual_card = create(:sales_lead, account: account, contact: contact, pipeline: other_pipeline, stage: create(:sales_stage, pipeline: other_pipeline), title: 'Card manual')
      lead = build_lead

      described_class.call(lead)

      expect(manual_card.reload.title).to eq('Card manual')
      expect(Sales::Lead.where(contact_id: contact.id).count).to eq(2)
    end

    it 'vincula a projeção ao lead do Engine, sem confundir dois leads do mesmo contato' do
      first = build_lead(telefone: '+5513991000001')
      second = build_lead(telefone: '+5513991000002')

      first_card = described_class.call(first)
      second_card = described_class.call(second)

      expect(first_card.operational_lead_id).to eq(first.lead_id)
      expect(second_card.operational_lead_id).to eq(second.lead_id)
      expect(first_card.id).not_to eq(second_card.id)
    end
  end

  describe 'tags computadas (§20.1)' do
    it 'marca lavinia quando modo_atendimento e lavinia' do
      lead = build_lead(modo_atendimento: 'lavinia')

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to eq(['lavinia'])
    end

    it 'marca humano quando modo_atendimento e humano' do
      lead = build_lead(modo_atendimento: 'humano')

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to eq(['humano'])
    end

    it 'adiciona callback quando agendamento_status e callback_registrado' do
      lead = build_lead(modo_atendimento: 'humano', agendamento_status: 'callback_registrado')

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to contain_exactly('humano', 'callback')
    end

    it 'atualiza as tags numa sincronizacao seguinte sem duplicar' do
      lead = build_lead(modo_atendimento: 'lavinia')
      described_class.call(lead)

      lead.update!(modo_atendimento: 'humano')
      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_tags']).to eq(['humano'])
    end

    it 'nao apaga outras chaves de custom_attributes ja existentes no card' do
      lead = build_lead
      sales_lead = described_class.call(lead)
      sales_lead.update!(custom_attributes: sales_lead.custom_attributes.merge('nota_manual' => 'vip'))

      lead.update!(modo_atendimento: 'humano')
      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['nota_manual']).to eq('vip')
      expect(sales_lead.custom_attributes['engine_tags']).to eq(['humano'])
    end
  end

  describe 'filtros do Kanban (§21.1)' do
    it 'grava os sete campos de filtro em custom_attributes.engine_filters' do
      lead = build_lead(
        modo_entrada: 'outbound', origem_lead: 'google_scraping', segmento: 'cafeteria',
        inbox_atual_id: 7, modo_atendimento: 'humano', responsavel_atual_id: 42, recuperacao_status: 'ativa'
      )

      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_filters']).to eq(
        'modo_entrada' => 'outbound', 'origem_lead' => 'google_scraping', 'segmento' => 'cafeteria',
        'inbox_atual_id' => 7, 'modo_atendimento' => 'humano', 'responsavel_atual_id' => 42,
        'recuperacao_status' => 'ativa'
      )
    end

    it 'atualiza os filtros numa sincronizacao seguinte' do
      lead = build_lead(recuperacao_status: 'inativa')
      described_class.call(lead)

      lead.update!(recuperacao_status: 'ativa')
      sales_lead = described_class.call(lead)

      expect(sales_lead.custom_attributes['engine_filters']['recuperacao_status']).to eq('ativa')
    end
  end
end
