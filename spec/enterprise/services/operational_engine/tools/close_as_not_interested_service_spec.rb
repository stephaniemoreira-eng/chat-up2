require 'rails_helper'

RSpec.describe OperationalEngine::Tools::CloseAsNotInterestedService do
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

  it 'encerra o lead como sem interesse' do
    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.lead_status).to eq('encerrado')
    expect(lead.motivo_encerramento).to eq('sem_interesse')
  end

  it 'não mexe em qualificacao_status' do
    lead.update!(qualificacao_status: 'em_qualificacao')

    perform

    expect(lead.reload.qualificacao_status).to eq('em_qualificacao')
  end

  it 'recusa quando já existe um agendamento confirmado' do
    lead.update!(confirmed_meeting_attributes)

    expect(perform).to eq(ok: false, reason: 'lead tem um agendamento confirmado')
    expect(lead.reload.lead_status).to eq('ativo')
  end

  it 'é idempotente -- não duplica o evento' do
    perform
    perform

    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'encerrado_sem_interesse').count).to eq(1)
  end

  # CP-01 -- P1-018-05: estado mais novo vence a ação antiga que esperava o lock.
  describe 'corrida com fato mais novo' do
    it 'reunião confirmada enquanto a ação esperava: não encerra' do
      persist_newer_fact_before_lock(**confirmed_meeting_attributes)

      expect(perform).to eq(ok: false, reason: 'lead tem um agendamento confirmado')
      expect(lead.reload.lead_status).to eq('ativo')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'encerrado_sem_interesse')).to be_empty
    end

    it 'humano assumiu enquanto a ação esperava: a Lavínia não altera o estado' do
      persist_newer_fact_before_lock(modo_atendimento: 'humano')

      expect(perform).to eq(ok: false, reason: 'lead em atendimento humano')
      expect(lead.reload.lead_status).to eq('ativo')
    end
  end
end
