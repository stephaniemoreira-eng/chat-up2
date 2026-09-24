require 'rails_helper'

# CP-16B -- P2-VAL-20 (decisão da Stéphanie em 24/09/2026): o commit do turno silencioso pós-devolução
# só grava continuidade; nenhuma decisão, timer ou ação sai dele. Arquivo próprio para não disputar o
# spec principal do ApplyStructuredOutputService com outros pacotes.
RSpec.describe OperationalEngine::ApplyStructuredOutputService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa',
                                    ultimo_ponto: 'aguardando_volume', resumo_oportunidade: 'restaurante')
  end

  def resync(**saida)
    described_class.new(account: account, conversation_id: conversation.display_id, saida: saida, ressincronizacao: true).call
  end

  it 'grava o ultimo_ponto novo que a Lavínia interpretou e registra a ressincronização' do
    result = resync(ultimo_ponto: 'aguardando_escolha_horario', resumo_oportunidade: 'restaurante, 300 kg/mês')

    expect(result).to include(ok: true)
    expect(lead.reload).to have_attributes(ultimo_ponto: 'aguardando_escolha_horario', resumo_oportunidade: 'restaurante, 300 kg/mês')
    event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'ressincronizacao_devolucao')
    expect(event.metadata['campos']).to contain_exactly('ultimo_ponto', 'resumo_oportunidade')
  end

  it '"SE NECESSÁRIO": ultimo_ponto vazio, nulo ou igual não sobrescreve' do
    resync(ultimo_ponto: '')
    resync(ultimo_ponto: nil)
    resync(ultimo_ponto: 'aguardando_volume')

    expect(lead.reload.ultimo_ponto).to eq('aguardando_volume')
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'ressincronizacao_devolucao').map { |e| e.metadata['campos'] }).to all(be_empty)
  end

  it 'aproveita fatos da conversa humana (whitelist), sem apagar os já persistidos' do
    resync(dados_extraidos: { volume_mensal_kg: 300, segmento: '' })

    expect(lead.reload).to have_attributes(volume_mensal_kg: 300)
  end

  it 'descarta decisão, aguardando_resposta e acao_sugerida: não qualifica, não encerra, não arma timer' do
    resync(decisao_qualificacao: 'nao_qualificado', aguardando_resposta: true, acao_sugerida: 'encerrar_nao_qualificado',
           ultimo_ponto: 'avaliando_viabilidade')

    expect(lead.reload).to have_attributes(
      ultimo_ponto: 'avaliando_viabilidade', qualificacao_status: 'em_qualificacao', lead_status: 'ativo', aguardando_resposta: false
    )
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'lead_nao_qualificado')).to be_empty
  end

  it 'também não qualifica quando a saída diz "qualificado"' do
    resync(decisao_qualificacao: 'qualificado', ultimo_ponto: 'avaliando_viabilidade')

    expect(lead.reload.etapa_prospect).to eq('em_conversa')
  end

  it 'lead que voltou para humano entre a devolução e o turno: nada é gravado' do
    lead.update!(modo_atendimento: 'humano')

    expect(resync(ultimo_ponto: 'outro_ponto')).to eq(ok: false, reason: 'lead em atendimento humano')
    expect(lead.reload.ultimo_ponto).to eq('aguardando_volume')
  end

  it 'fora do modo de ressincronização, o commit segue como antes' do
    described_class.new(account: account, conversation_id: conversation.display_id, saida: { aguardando_resposta: true }).call

    expect(lead.reload.aguardando_resposta).to be(true)
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'ressincronizacao_devolucao')).to be_empty
  end
end
