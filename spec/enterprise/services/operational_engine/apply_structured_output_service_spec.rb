require 'rails_helper'

# CP-03 -- P1-021-02 (SSOT §3.5, §12.4, §13.3).
RSpec.describe OperationalEngine::ApplyStructuredOutputService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa',
                                    modelo_atual: 'lavagem própria', segmento: 'restaurante')
  end

  def perform(**saida)
    described_class.new(account: account, conversation_id: conversation.display_id, saida: saida).call
  end

  it 'um turno completo persiste fatos + qualificação + aguardando_resposta + ultimo_ponto + resumo' do
    result = perform(
      dados_extraidos: { dor_oportunidade: 'fila de roupas', volume_mensal_kg: 350, retiradas_semana: 2, intencao_comercial: 'quer_avancar' },
      decisao_qualificacao: 'qualificado', aguardando_resposta: true,
      ultimo_ponto: 'perguntei o CEP', resumo_oportunidade: 'restaurante com 350 kg/mês, quer avançar'
    )

    expect(result[:ok]).to be(true)
    expect(lead.reload).to have_attributes(
      dor_oportunidade: 'fila de roupas', volume_mensal_kg: 350, retiradas_semana: 2, intencao_comercial: 'quer_avancar',
      qualificacao_status: 'qualificado', etapa_prospect: 'qualificado', aguardando_resposta: true,
      ultimo_ponto: 'perguntei o CEP', resumo_oportunidade: 'restaurante com 350 kg/mês, quer avançar'
    )
  end

  it 'null, vazio ou ausente nunca apaga um valor válido já persistido' do
    perform(dados_extraidos: { modelo_atual: nil, segmento: '' }, ultimo_ponto: nil)

    lead.reload
    expect(lead.modelo_atual).to eq('lavagem própria')
    expect(lead.segmento).to eq('restaurante')
  end

  it 'ignora e reporta chave fora da whitelist ou valor de tipo inválido, sem persistir' do
    result = perform(dados_extraidos: { etapa_prospect: 'agendado', cobertura_status: 'atendida', intencao_comercial: 'inventado',
                                        volume_mensal_kg: -3 })

    expect(result[:ignorados]).to contain_exactly('etapa_prospect', 'cobertura_status', 'intencao_comercial', 'volume_mensal_kg')
    lead.reload
    expect(lead.etapa_prospect).to eq('em_conversa')
    expect(lead.cobertura_status).to be_nil
  end

  it 'qualificado grava qualificado_em e os eventos lead_qualificado e etapa_alterada (§13.3)' do
    perform(decisao_qualificacao: 'qualificado')

    expect(lead.reload.qualificado_em).to be_present
    expect(OperationalEngine::LeadEvent.where(lead: lead).pluck(:event_type)).to include('lead_qualificado', 'etapa_alterada')
  end

  it 'nao_qualificado encerra o lead com o motivo, exceto com reunião confirmada' do
    perform(decisao_qualificacao: 'nao_qualificado')
    lead.reload
    expect([lead.qualificacao_status, lead.lead_status, lead.motivo_encerramento]).to eq(%w[nao_qualificado encerrado nao_qualificado])

    other = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513990000001', **confirmed_meeting_attributes)
    other_conversation = create(:conversation, account: account, contact: create(:contact, account: account, phone_number: other.telefone))
    result = described_class.new(account: account, conversation_id: other_conversation.display_id,
                                 saida: { decisao_qualificacao: 'nao_qualificado' }).call
    expect(result[:avisos]).to include(/reunião confirmada/)
    expect(other.reload.lead_status).to eq('ativo')
  end

  it 'em_qualificacao não regride quem já é qualificado' do
    lead.update!(qualificacao_status: 'qualificado', etapa_prospect: 'qualificado')

    perform(decisao_qualificacao: 'em_qualificacao')

    expect(lead.reload.qualificacao_status).to eq('qualificado')
  end

  it 'em modo humano não aplica nada (§12.4)' do
    lead.update!(modo_atendimento: 'humano')

    result = perform(dados_extraidos: { dor_oportunidade: 'x' }, decisao_qualificacao: 'qualificado')

    expect(result).to eq(ok: false, reason: 'lead em atendimento humano')
    expect(lead.reload.dor_oportunidade).to be_nil
  end

  it 'recusa decisao_qualificacao fora do contrato' do
    expect(perform(decisao_qualificacao: 'quase')).to eq(ok: false, reason: 'decisao_qualificacao inválida')
  end

  it 'o Snapshot do turno seguinte reflete os dados persistidos' do
    perform(dados_extraidos: { cep: '11000-000' }, ultimo_ponto: 'pedir volume')

    snapshot = OperationalEngine::SnapshotBuilder.call(lead.reload)
    expect(snapshot[:conhecimento][:cep]).to eq('11000-000')
    expect(snapshot[:continuidade][:ultimo_ponto]).to eq('pedir volume')
  end
end
