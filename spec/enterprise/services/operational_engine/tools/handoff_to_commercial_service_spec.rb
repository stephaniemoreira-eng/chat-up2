require 'rails_helper'

RSpec.describe OperationalEngine::Tools::HandoffToCommercialService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(
      conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
      etapa_prospect: 'qualificado', qualificacao_status: 'qualificado', nome: 'Ana', empresa: 'Hotel Mar',
      aguardando_resposta: true, recuperacao_status: 'ativa', proxima_recuperacao_em: 1.day.from_now
    )
  end

  def perform(motivo: 'avanco_comercial')
    described_class.new(account: account, conversation_id: conversation.display_id, motivo_handoff: motivo).call
  end

  def events(type)
    OperationalEngine::LeadEvent.where(lead: lead, event_type: type)
  end

  it 'retorna erro quando a conversa não existe' do
    result = described_class.new(account: account, conversation_id: -1, motivo_handoff: 'avanco_comercial').call

    expect(result).to eq(ok: false, reason: 'conversa não encontrada')
  end

  it 'recusa motivo_handoff fora do enum' do
    expect(perform(motivo: 'chute_qualquer')).to eq(ok: false, reason: 'motivo_handoff inválido')
    expect(lead.reload.modo_atendimento).to eq('lavinia')
  end

  it 'recusa um lead em não-contatar' do
    lead.update!(nao_contatar: true)

    expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
  end

  # CP-05 -- P1-018-01 (SSOT §17.2).
  describe 'handoff real' do
    it 'grava todas as dimensões do §17.2: frente Comercial, humano, oportunidade, recovery encerrada' do
      perform(motivo: 'orcamento_personalizado')

      lead.reload
      expect(lead.frente_operacional).to eq('comercial')
      expect(lead.modo_atendimento).to eq('humano')
      expect(lead.modo_atendimento_entrou_em).to be_present
      expect(lead.etapa_comercial).to eq('oportunidade')
      expect(lead.motivo_handoff).to eq('orcamento_personalizado')
      expect(lead.aguardando_resposta).to be(false)
      expect([lead.recuperacao_status, lead.proxima_recuperacao_em]).to eq(['inativa', nil])
    end

    # LACUNA do SSOT (OperationalEngine::CommercialResponsibleResolver): sem regra/config para
    # escolher o responsável Comercial, o handoff não inventa um -- e diz isso explicitamente.
    it 'sem responsável resolvível, deixa o responsável pendente e explícito no retorno e no evento' do
      result = perform

      expect(result).to eq(ok: true, responsavel_pendente: true)
      expect(lead.reload.responsavel_atual_id).to be_nil
      expect(events('handoff_comercial').first.metadata['responsavel_pendente']).to be(true)
    end

    it 'registra handoff_comercial com transições e snapshot §17.3, mais os eventos canônicos de cada semântica' do
      perform

      handoff = events('handoff_comercial').first
      expect(handoff.source).to eq('lavinia')
      expect(handoff.metadata['transicoes']['frente_operacional']).to eq('de' => 'prospeccao', 'para' => 'comercial')
      expect(handoff.metadata['snapshot']).to include('nome' => 'Ana', 'empresa' => 'Hotel Mar', 'motivo_handoff' => 'avanco_comercial',
                                                      'conversation_id' => conversation.display_id)
      expect(events('frente_operacional_alterada').first.metadata).to include('de' => 'prospeccao', 'para' => 'comercial')
      expect(events('modo_atendimento_alterado').first.metadata).to include('de' => 'lavinia', 'para' => 'humano')
      expect(events('oportunidade_criada').count).to eq(1)
    end

    it 'projeta o card Comercial em Oportunidade e a tag HUMANO no Prospect' do
      perform

      comercial = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'comercial' })
      prospect = Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'prospect' })
      expect(comercial.stage.engine_stage_key).to eq('oportunidade')
      expect(prospect.custom_attributes['engine_tags']).to include('humano')
    end

    it 'não rebaixa uma oportunidade que já avançou' do
      lead.update!(etapa_comercial: 'em_acompanhamento')

      perform

      expect(lead.reload.etapa_comercial).to eq('em_acompanhamento')
      expect(events('oportunidade_criada')).to be_empty
    end
  end

  # CP-05 -- P1-018-02 (SSOT §18.4: intervenção humana não é handoff).
  describe 'idempotência pelo estado integral do handoff' do
    it 'humano já atendendo em Prospecção: o handoff completa a passagem para o Comercial mantendo o responsável' do
      lead.update!(modo_atendimento: 'humano', responsavel_atual_id: 42, modo_atendimento_entrou_em: 1.hour.ago.change(usec: 0),
                   aguardando_resposta: false, recuperacao_status: 'inativa', proxima_recuperacao_em: nil)
      entrou_em = lead.modo_atendimento_entrou_em

      expect(perform).to eq(ok: true)

      lead.reload
      expect(lead.frente_operacional).to eq('comercial')
      expect(lead.etapa_comercial).to eq('oportunidade')
      expect(lead.responsavel_atual_id).to eq(42)
      expect(lead.modo_atendimento_entrou_em).to eq(entrou_em)
      expect(events('handoff_comercial').count).to eq(1)
      expect(events('modo_atendimento_alterado')).to be_empty
    end

    it 'replay com o handoff já integral não duplica eventos nem troca o motivo original' do
      perform(motivo: 'avanco_comercial')

      expect { perform(motivo: 'excecao') }.not_to(change { OperationalEngine::LeadEvent.where(lead: lead).count })
      expect(lead.reload.motivo_handoff).to eq('avanco_comercial')
    end
  end

  # CP-01 -- P1-018-05.
  it 'opt-out entrou enquanto a ação esperava: não faz handoff' do
    persist_newer_fact_before_lock(nao_contatar: true)

    expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
    expect(lead.reload.modo_atendimento).to eq('lavinia')
    expect(events('handoff_comercial')).to be_empty
  end

  # CP-16A -- P2-VAL-16 (decisão da Stéphanie em 24/09/2026: responsável Comercial do handoff pedido
  # pela Lavínia = "DANILO", configurado por conta em UpSales::AgentTenant).
  describe 'responsável Comercial configurado na conta (P2-VAL-16)' do
    let(:danilo) { create(:user, account: account) }

    before { create(:up_sales_agent_tenant, account: account, commercial_responsible_user_id: danilo.id) }

    it 'grava o usuário configurado como responsável, sem pendência' do
      result = perform

      expect(result).to eq(ok: true)
      expect(lead.reload.responsavel_atual_id).to eq(danilo.id)
      handoff = events('handoff_comercial').first
      expect(handoff.metadata['responsavel_pendente']).to be(false)
      expect(handoff.metadata['transicoes']['responsavel_atual_id']).to eq('de' => nil, 'para' => danilo.id)
      expect(events('responsavel_alterado').sole.metadata).to include('de' => nil, 'para' => danilo.id, 'motivo' => 'handoff_comercial')
    end

    it 'humano que já era responsável continua sendo o responsável (não troca pelo configurado)' do
      lead.update!(modo_atendimento: 'humano', responsavel_atual_id: 42, modo_atendimento_entrou_em: 1.hour.ago)

      perform

      expect(lead.reload.responsavel_atual_id).to eq(42)
      expect(events('responsavel_alterado')).to be_empty
    end
  end
end
