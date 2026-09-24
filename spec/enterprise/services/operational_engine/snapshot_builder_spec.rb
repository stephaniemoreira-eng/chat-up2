require 'rails_helper'

RSpec.describe OperationalEngine::SnapshotBuilder do
  let(:account) { create(:account) }

  def perform(lead)
    described_class.call(lead)
  end

  it 'espelha leadSnapshotSchema (up2-agents) campo a campo' do
    lead = OperationalEngine::Lead.create!(
      conta_id: account.id,
      telefone: '+5513991234567',
      nome: 'Danilo',
      empresa: 'Lava e Pronto',
      segmento: 'lavanderia',
      regiao: 'Santos/SP',
      origem_lead: 'inbound_direto',
      modo_entrada: 'inbound',
      tipo_entrada: 'novo',
      inbox_entrada_id: 42,
      inbox_atual_id: 43,
      qualificacao_status: 'em_qualificacao',
      orcamento_status: 'informado',
      agendamento_status: 'nao_iniciado', # CP-04 (P2-017-01): confirmado exige Calendar real
      recuperacao_status: 'inativa',
      frente_operacional: 'comercial',
      modo_atendimento: 'lavinia',
      nao_contatar: false,
      modelo_atual: 'concorrente X',
      dor_oportunidade: 'fila grande',
      impacto: 'perde cliente',
      intencao_comercial: 'quer_orcamento',
      cep: '11000-000',
      cobertura_status: 'atendida',
      volume_mensal_kg: 120.5,
      retiradas_semana: 3,
      ultimo_ponto: 'aguardando confirmação de horário',
      resumo_oportunidade: 'quer trocar de fornecedor',
      ultima_interacao_em: Time.zone.parse('2026-09-21T10:00:00-03:00')
    )

    snapshot = perform(lead)

    expect(snapshot).to eq(
      contract_version: 1,
      identidade: {
        lead_id: lead.lead_id,
        nome: 'Danilo',
        empresa: 'Lava e Pronto',
        telefone: '+5513991234567',
        segmento: 'lavanderia',
        regiao: 'Santos/SP'
      },
      aquisicao: {
        origem_lead: 'inbound_direto',
        modo_entrada: 'inbound',
        tipo_entrada: 'novo',
        inbox_entrada_id: '42',
        inbox_atual_id: '43'
      },
      estado: {
        etapa_prospect: 'backlog',
        qualificacao_status: 'em_qualificacao',
        orcamento_status: 'informado',
        agendamento_status: 'nao_iniciado',
        recuperacao_status: 'inativa',
        frente_operacional: 'comercial',
        modo_atendimento: 'lavinia',
        nao_contatar: false
      },
      conhecimento: {
        modelo_atual: 'concorrente X',
        dor_oportunidade: 'fila grande',
        impacto: 'perde cliente',
        intencao_comercial: 'quer_orcamento',
        cep: '11000-000',
        cobertura_status: 'atendida',
        volume_mensal_kg: 120.5,
        retiradas_semana: 3
      },
      continuidade: {
        ultimo_ponto: 'aguardando confirmação de horário',
        resumo_oportunidade: 'quer trocar de fornecedor',
        # Mesmo instante que o create! acima, mas via lead.iso8601 -- não um literal escrito à
        # mão -- porque o Time.zone efetivo no ambiente do teste decide se ele sai em -03:00 ou
        # em Z (UTC), e isso não é o que este teste quer travar.
        ultima_interacao_em: lead.ultima_interacao_em.iso8601,
        contexto_execucao: 'conversa'
      },
      mensagens_recentes_relevantes: [],
      mensagem_atual: nil,
      source: 'engine'
    )
  end

  it 'usa null em vez de omitir campo ausente -- o agente deve ver "desconhecido", nunca uma chave faltando' do
    lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991111111')

    snapshot = perform(lead)

    expect(snapshot[:identidade][:nome]).to be_nil
    expect(snapshot[:aquisicao][:inbox_entrada_id]).to be_nil
    expect(snapshot[:conhecimento][:volume_mensal_kg]).to be_nil
    expect(snapshot[:continuidade][:ultima_interacao_em]).to be_nil
  end

  # CP-03 (P1-017-02): o contexto vem do DISPARADOR, informado por quem orquestra o turno -- não
  # é inferido da fotografia do lead. O mesmo estado produz contextos diferentes.
  describe 'contexto_execucao' do
    let(:lead) do
      OperationalEngine::Lead.create!(
        conta_id: account.id, telefone: '+5513992222222',
        etapa_prospect: 'contatado', recuperacao_status: 'ativa', agendamento_status: 'em_andamento'
      )
    end

    %w[conversa primeiro_contato recuperacao agenda].each do |contexto|
      it "reflete o disparador: #{contexto}" do
        snapshot = described_class.call(lead, trigger: { contexto_execucao: contexto })

        expect(snapshot[:continuidade][:contexto_execucao]).to eq(contexto)
      end
    end

    it 'sem disparador informado é conversa -- nunca "agenda"/"recuperacao" adivinhados do estado' do
      expect(described_class.call(lead)[:continuidade][:contexto_execucao]).to eq('conversa')
    end

    it 'carrega a mensagem atual e o histórico recente montados em torno do disparador' do
      atual = { message_id: '7', texto: 'oi', timestamp: '2026-09-23T10:00:00-03:00' }
      snapshot = described_class.call(lead, trigger: { mensagem_atual: atual, mensagens_recentes_relevantes: [atual] })

      expect(snapshot[:mensagem_atual]).to eq(atual)
      expect(snapshot[:mensagens_recentes_relevantes]).to eq([atual])
    end
  end
end
