require 'rails_helper'

RSpec.describe OperationalEngine::Tools::RegisterCallbackService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id)
  end

  def perform
    described_class.new(account: account, conversation_id: conversation.display_id).call
  end

  it 'retorna erro quando a conversa não existe' do
    result = described_class.new(account: account, conversation_id: -1).call

    expect(result).to eq(ok: false, reason: 'conversa não encontrada')
  end

  it 'registra o callback e abre oportunidade Comercial' do
    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.agendamento_status).to eq('callback_registrado')
    expect(lead.etapa_comercial).to eq('oportunidade')
  end

  it 'não é conversão -- nunca toca conversao_em/tipo_conversao' do
    perform

    lead.reload
    expect(lead.conversao_em).to be_nil
    expect(lead.tipo_conversao).to be_nil
  end

  it 'não rebaixa uma oportunidade que já avançou' do
    lead.update!(etapa_comercial: 'ganho')

    perform

    expect(lead.reload.etapa_comercial).to eq('ganho')
  end

  it 'grava o evento callback_registrado' do
    perform

    event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'callback_registrado')
    expect(event).to be_present
    expect(event.source).to eq('lavinia')
  end

  it 'sincroniza a tag CALLBACK no card Prospect e cria o card Comercial' do
    perform

    sales_lead = Sales::Lead.find_by(contact_id: contact.id)
    expect(sales_lead.custom_attributes['engine_tags']).to include('callback')

    comercial_card = Sales::Lead.joins(:pipeline).find_by(contact_id: contact.id, sales_pipelines: { engine_kind: 'comercial' })
    expect(comercial_card).to be_present
  end

  # CP-09 -- P1-VAL-04 (SSOT §8.2 "Callback", §16.2, §13.3, §23.1, §23.2, teste 28.16).
  describe 'estado completo do teste 28.16' do
    def events(type)
      OperationalEngine::LeadEvent.where(lead: lead, event_type: type)
    end

    before { lead.update!(etapa_prospect: 'em_conversa', etapa_entrou_em: 1.day.ago) }

    it 'garante Prospect Qualificado no mesmo lock (§13.3), sem conversão' do
      expect(perform).to eq(ok: true)

      lead.reload
      expect(lead.etapa_prospect).to eq('qualificado')
      expect(lead.qualificacao_status).to eq('qualificado')
      expect(lead.qualificado_em).to be_present
      expect(lead.agendamento_status).to eq('callback_registrado')
      expect(lead.etapa_comercial).to eq('oportunidade')
      expect([lead.conversao_em, lead.tipo_conversao]).to eq([nil, nil])
    end

    it 'registra lead_qualificado, etapa_alterada, oportunidade_criada e callback_registrado' do
      perform

      expect(events('lead_qualificado').count).to eq(1)
      expect(events('etapa_alterada').first.metadata).to include('de' => 'em_conversa', 'para' => 'qualificado')
      expect(events('oportunidade_criada').first.metadata).to include('etapa_comercial' => 'oportunidade', 'motivo' => 'callback_registrado')
      expect(events('callback_registrado').count).to eq(1)
    end

    it 'não é handoff: frente operacional e modo de atendimento não mudam' do
      perform

      lead.reload
      expect(lead.frente_operacional).to eq('prospeccao')
      expect(lead.modo_atendimento).to eq('lavinia')
    end

    it 'projeta Qualificado + CALLBACK no Prospect e Oportunidade + CALLBACK no Comercial' do
      perform

      prospect = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'prospect' })
      comercial = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'comercial' })
      expect(prospect.stage.engine_stage_key).to eq('qualificado')
      expect(prospect.custom_attributes['engine_tags']).to include('callback')
      expect(comercial.stage.engine_stage_key).to eq('oportunidade')
      expect(comercial.custom_attributes['engine_tags']).to include('callback')
    end

    it 'não regride um Agendado cuja reunião foi cancelada (§8.3)' do
      lead.update!(confirmed_meeting_attributes.merge(agendamento_status: 'cancelado'))

      perform

      expect(lead.reload.etapa_prospect).to eq('agendado')
      expect(lead.agendamento_status).to eq('callback_registrado')
    end

    it 'mantém a oportunidade existente sem novo oportunidade_criada' do
      lead.update!(etapa_comercial: 'em_acompanhamento')

      perform

      expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
      expect(events('oportunidade_criada')).to be_empty
    end
  end

  describe 'guardas dentro do lock (como as demais tools da Lavínia)' do
    def expect_nothing_changed(result, reason)
      expect(result).to eq(ok: false, reason: reason)
      lead.reload
      expect(lead.agendamento_status).not_to eq('callback_registrado')
      expect(lead.etapa_comercial).to be_nil
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: %w[callback_registrado oportunidade_criada lead_qualificado])).to be_empty
    end

    it 'recusa lead em atendimento humano' do
      lead.update!(modo_atendimento: 'humano')

      expect_nothing_changed(perform, 'lead em atendimento humano')
    end

    it 'recusa lead em não-contatar' do
      lead.update!(nao_contatar: true)

      expect_nothing_changed(perform, 'lead está em não-contatar')
    end

    it 'recusa lead encerrado' do
      lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')

      expect_nothing_changed(perform, 'lead encerrado')
    end

    it 'recusa lead julgado não qualificado' do
      lead.update!(qualificacao_status: 'nao_qualificado')

      expect_nothing_changed(perform, 'lead não qualificado')
      expect(lead.reload.qualificacao_status).to eq('nao_qualificado')
    end

    it 'recusa quando já existe reunião confirmada (não apaga o fato da reunião real)' do
      lead.update!(confirmed_meeting_attributes)

      expect(perform).to eq(ok: false, reason: 'lead tem uma reunião confirmada')
      expect(lead.reload.agendamento_status).to eq('confirmado')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'callback_registrado')).to be_empty
    end

    it 'corrida: humano que assumiu enquanto a ação esperava o lock vence' do
      persist_newer_fact_before_lock(modo_atendimento: 'humano')

      expect_nothing_changed(perform, 'lead em atendimento humano')
    end
  end

  describe 'idempotência (§23.1)' do
    it 'repetir o registro não duplica eventos nem altera o estado' do
      perform
      snapshot = lead.reload.attributes.except('atualizado_em')

      expect { expect(perform).to eq(ok: true) }.not_to change(OperationalEngine::LeadEvent, :count)
      expect(lead.reload.attributes.except('atualizado_em')).to eq(snapshot)
    end

    it 'callback já pendente com estado completo é no-op' do
      lead.update!(pending_callback_attributes)

      expect { expect(perform).to eq(ok: true) }.not_to change(OperationalEngine::LeadEvent, :count)
    end

    it 'callback pendente incompleto (sem Qualificado) é completado sem novo callback_registrado' do
      lead.update!(agendamento_status: 'callback_registrado')

      perform

      expect(lead.reload.etapa_prospect).to eq('qualificado')
      expect(lead.etapa_comercial).to eq('oportunidade')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'callback_registrado')).to be_empty
    end
  end
end
