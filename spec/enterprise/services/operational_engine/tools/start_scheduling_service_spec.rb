require 'rails_helper'

RSpec.describe OperationalEngine::Tools::StartSchedulingService do
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

  it 'recusa um lead em não-contatar' do
    lead.update!(nao_contatar: true)

    expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
  end

  it 'marca o agendamento como em_andamento e termina em Prospect Qualificado' do
    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.agendamento_status).to eq('em_andamento')
    expect(lead.etapa_prospect).to eq('qualificado')
  end

  it 'é idempotente -- chamar de novo já em_andamento não duplica o evento' do
    perform
    perform

    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'agendamento_iniciado').count).to eq(1)
  end

  # CP-04 -- P1-018-03 (§16.1 + rota curta §13.2/§13.3).
  describe 'rota curta: intenção explícita de agendar qualifica no mesmo lock' do
    it 'lead em conversa vira Qualificado com qualificado_em e eventos lead_qualificado/etapa_alterada' do
      lead.update!(etapa_prospect: 'em_conversa', qualificacao_status: 'em_qualificacao')

      expect(perform).to eq(ok: true)

      lead.reload
      expect(lead.qualificacao_status).to eq('qualificado')
      expect(lead.etapa_prospect).to eq('qualificado')
      expect(lead.qualificado_em).to be_present
      types = OperationalEngine::LeadEvent.where(lead: lead).pluck(:event_type)
      expect(types).to include('lead_qualificado', 'etapa_alterada', 'agendamento_iniciado')
    end

    it 'lead ja Qualificado nao regrava qualificado_em nem duplica lead_qualificado' do
      original = 2.days.ago.change(usec: 0)
      lead.update!(etapa_prospect: 'qualificado', qualificacao_status: 'qualificado', qualificado_em: original)

      perform

      expect(lead.reload.qualificado_em).to eq(original)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'lead_qualificado')).to be_empty
    end

    it 'nunca termina fora de Qualificado nem reabre lead encerrado ou nao qualificado' do
      lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')
      expect(perform).to eq(ok: false, reason: 'lead encerrado')

      lead.update!(lead_status: 'ativo', motivo_encerramento: nil, qualificacao_status: 'nao_qualificado')
      expect(perform).to eq(ok: false, reason: 'lead não qualificado')
      expect(lead.reload.agendamento_status).to eq('nao_iniciado')
    end
  end

  it 'recusa quando ja existe reuniao confirmada' do
    lead.update!(confirmed_meeting_attributes)

    expect(perform).to eq(ok: false, reason: 'já existe um compromisso ativo para este lead')
    expect(lead.reload.agendamento_status).to eq('confirmado')
  end

  it 'recusa quando o callback ja foi realizado' do
    lead.update!(agendamento_status: 'callback_realizado', callback_realizado_em: Time.current)

    expect(perform).to eq(ok: false, reason: 'já existe um compromisso ativo para este lead')
  end

  # CP-04 -- P1-018-04 (§16.4): callback pendente pode evoluir para reunião, mas só o sucesso real
  # do Calendar o substitui.
  it 'callback pendente: aceita negociar reuniao sem trocar o callback por em_andamento' do
    lead.update!(pending_callback_attributes)

    expect(perform).to eq(ok: true, callback_pendente: true)
    expect(lead.reload.agendamento_status).to eq('callback_registrado')
  end

  it 'permite reiniciar a partir de cancelado' do
    lead.update!(agendamento_status: 'cancelado')

    expect(perform).to eq(ok: true)
    expect(lead.reload.agendamento_status).to eq('em_andamento')
  end

  # CP-01 -- P1-018-05.
  describe 'corrida com fato mais novo' do
    it 'callback registrado enquanto a ação esperava: não sobrescreve para em_andamento' do
      persist_newer_fact_before_lock(**pending_callback_attributes)

      expect(perform).to eq(ok: true, callback_pendente: true)
      expect(lead.reload.agendamento_status).to eq('callback_registrado')
    end

    it 'reunião confirmada enquanto a ação esperava: recusa' do
      persist_newer_fact_before_lock(**confirmed_meeting_attributes)

      expect(perform).to eq(ok: false, reason: 'já existe um compromisso ativo para este lead')
      expect(lead.reload.agendamento_status).to eq('confirmado')
    end

    it 'opt-out entrou enquanto a ação esperava: não inicia agendamento' do
      persist_newer_fact_before_lock(nao_contatar: true)

      expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
      expect(lead.reload.agendamento_status).not_to eq('em_andamento')
    end

    it 'humano assumiu enquanto a ação esperava: não inicia agendamento' do
      persist_newer_fact_before_lock(modo_atendimento: 'humano')

      expect(perform).to eq(ok: false, reason: 'lead em atendimento humano')
    end
  end
end
