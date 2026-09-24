require 'rails_helper'

RSpec.describe OperationalEngine::Tools::StartBudgetService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id)
  end

  def perform
    described_class.new(account: account, conversation_id: conversation.id).call
  end

  it 'retorna erro quando a conversa não existe' do
    result = described_class.new(account: account, conversation_id: -1).call

    expect(result).to eq(ok: false, reason: 'conversa não encontrada')
  end

  it 'recusa um lead em não-contatar' do
    lead.update!(nao_contatar: true)

    expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
  end

  it 'inicia o dimensionamento de orçamento' do
    result = perform

    expect(result).to eq(ok: true)
    expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
  end

  it 'é idempotente -- não regride um orçamento que já avançou' do
    lead.update!(orcamento_status: 'informado')

    perform

    expect(lead.reload.orcamento_status).to eq('informado')
  end

  it 'grava o evento orcamento_iniciado só na primeira vez' do
    perform
    perform

    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'orcamento_iniciado').count).to eq(1)
  end

  # CP-01 -- P1-018-05.
  describe 'corrida com fato mais novo' do
    it 'opt-out entrou enquanto a ação esperava: não inicia orçamento' do
      persist_newer_fact_before_lock(nao_contatar: true)

      expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
      expect(lead.reload.orcamento_status).to eq('nao_solicitado')
    end

    it 'humano assumiu enquanto a ação esperava: não inicia orçamento' do
      persist_newer_fact_before_lock(modo_atendimento: 'humano')

      expect(perform).to eq(ok: false, reason: 'lead em atendimento humano')
      expect(lead.reload.orcamento_status).to eq('nao_solicitado')
    end
  end
end
