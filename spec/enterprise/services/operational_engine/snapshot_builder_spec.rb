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
      agendamento_status: 'confirmado',
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
        agendamento_status: 'confirmado',
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

  describe 'contexto_execucao' do
    it 'é agenda quando o agendamento está em andamento' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513992222222', agendamento_status: 'em_andamento')

      expect(perform(lead)[:continuidade][:contexto_execucao]).to eq('agenda')
    end

    it 'é recuperacao quando a recuperação está ativa e o lead está em contatado' do
      lead = OperationalEngine::Lead.create!(
        conta_id: account.id, telefone: '+5513993333333',
        etapa_prospect: 'contatado', recuperacao_status: 'ativa'
      )

      expect(perform(lead)[:continuidade][:contexto_execucao]).to eq('recuperacao')
    end

    it 'é conversa no caso default' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513994444444')

      expect(perform(lead)[:continuidade][:contexto_execucao]).to eq('conversa')
    end
  end
end
