require 'rails_helper'

RSpec.describe OperationalEngine::Tools::HandoffToCommercialService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(
      conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
      aguardando_resposta: true, recuperacao_status: 'ativa', proxima_recuperacao_em: 1.day.from_now
    )
  end

  def perform(motivo: 'avanco_comercial')
    described_class.new(account: account, conversation_id: conversation.display_id, motivo_handoff: motivo).call
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

  it 'passa o atendimento pra humano, sem responsável ainda' do
    result = perform(motivo: 'orcamento_personalizado')

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.modo_atendimento).to eq('humano')
    expect(lead.responsavel_atual_id).to be_nil
    expect(lead.motivo_handoff).to eq('orcamento_personalizado')
  end

  it 'para de esperar resposta e desliga recovery, como o takeover humano' do
    perform

    lead.reload
    expect(lead.aguardando_resposta).to eq(false)
    expect(lead.recuperacao_status).to eq('inativa')
    expect(lead.proxima_recuperacao_em).to be_nil
  end

  it 'cria a oportunidade Comercial se ainda não havia nenhuma' do
    perform

    expect(lead.reload.etapa_comercial).to eq('oportunidade')
  end

  it 'não rebaixa uma oportunidade que já avançou' do
    lead.update!(etapa_comercial: 'ganho')

    perform

    expect(lead.reload.etapa_comercial).to eq('ganho')
  end

  it 'é idempotente -- já em modo humano não reescreve nem duplica evento' do
    perform(motivo: 'avanco_comercial')
    perform(motivo: 'excecao')

    lead.reload
    expect(lead.motivo_handoff).to eq('avanco_comercial')
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'handoff_comercial').count).to eq(1)
  end

  # CP-01 -- P1-018-05.
  it 'opt-out entrou enquanto a ação esperava: não faz handoff' do
    persist_newer_fact_before_lock(nao_contatar: true)

    expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
    expect(lead.reload.modo_atendimento).to eq('lavinia')
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'handoff_comercial')).to be_empty
  end
end
