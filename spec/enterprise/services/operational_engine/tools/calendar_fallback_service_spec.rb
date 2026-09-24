require 'rails_helper'

# CP-16B (P2-VAL-19) -- decisão da Stéphanie em 24/09/2026: na segunda falha do Calendar ao agendar,
# callback do Danilo registrado + texto fixo para o lead (nunca "agendado").
RSpec.describe OperationalEngine::Tools::CalendarFallbackService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id)
  end

  def perform(ferramenta: 'criar_evento')
    described_class.new(account: account, conversation_id: conversation.display_id, ferramenta: ferramenta).call
  end

  it 'registra o callback pelo caminho do CP-09 (Qualificado + CALLBACK + oportunidade)' do
    result = perform

    expect(result).to include(ok: true, callback: 'registrado', motivo: 'falha_calendar')
    lead.reload
    expect(lead.agendamento_status).to eq('callback_registrado')
    expect(lead.qualificacao_status).to eq('qualificado')
    expect(lead.etapa_comercial).to eq('oportunidade')
  end

  it 'deixa a origem explícita no evento callback_registrado e grava a trilha da falha dupla' do
    perform

    callback = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'callback_registrado')
    expect(callback.metadata).to include('motivo' => 'falha_calendar', 'origem' => 'criar_evento')
    trilha = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'agendamento_falhou_callback')
    expect(trilha.metadata).to include('motivo' => 'falha_calendar', 'ferramenta' => 'criar_evento', 'tentativas' => 2)
  end

  it 'devolve o texto fixo padrão, fiel à decisão, que nunca diz "agendado"' do
    result = perform

    expect(result[:mensagem_lead]).to eq(described_class::DEFAULT_MESSAGE)
    expect(result[:mensagem_lead]).to include('Danilo')
    expect(result[:mensagem_lead]).not_to match(/agendad/i)
  end

  it 'usa o responsável Comercial do resolver quando existe, sem tocar responsavel_atual_id' do
    allow(OperationalEngine::CommercialResponsibleResolver).to receive(:call).and_return(77)

    result = perform

    expect(result).to include(responsavel_comercial_id: 77, responsavel_pendente: false)
    expect(OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'callback_registrado').metadata['responsavel_comercial_id']).to eq(77)
    expect(lead.reload.responsavel_atual_id).to be_nil
    expect(lead.modo_atendimento).to eq('lavinia')
  end

  it 'sem responsável configurado, o callback fica com responsavel_pendente' do
    expect(perform).to include(ok: true, responsavel_comercial_id: nil, responsavel_pendente: true)
  end

  describe 'texto configurado' do
    it 'usa o texto da conta antes do da ENV' do
      account.update!(custom_attributes: { described_class::ACCOUNT_MESSAGE_KEY => 'O Danilo te chama em breve.' })

      with_modified_env(UP_SALES_CALENDAR_FALLBACK_MESSAGE: 'Texto da ENV.') do
        expect(perform[:mensagem_lead]).to eq('O Danilo te chama em breve.')
      end
    end

    it 'usa o texto da ENV quando a conta não tem' do
      with_modified_env(UP_SALES_CALENDAR_FALLBACK_MESSAGE: 'O Danilo fala com você logo.') do
        expect(perform[:mensagem_lead]).to eq('O Danilo fala com você logo.')
      end
    end

    it 'troca pelo padrão um texto configurado que diga "agendado" (28.15)' do
      with_modified_env(UP_SALES_CALENDAR_FALLBACK_MESSAGE: 'Pronto, sua reunião foi agendada!') do
        expect(perform[:mensagem_lead]).to eq(described_class::DEFAULT_MESSAGE)
      end
    end
  end

  describe 'callback que não pode ser registrado (nenhuma mensagem sai)' do
    it 'lead em atendimento humano' do
      lead.update!(modo_atendimento: 'humano')

      expect(perform).to eq(ok: false, reason: 'lead em atendimento humano')
      expect(lead.reload.agendamento_status).to eq('nao_iniciado')
    end

    it 'lead em não-contatar' do
      lead.update!(nao_contatar: true)

      expect(perform).to eq(ok: false, reason: 'lead está em não-contatar')
    end

    it 'lead com reunião confirmada (a 1ª tentativa, na verdade, deu certo)' do
      lead.update!(agendamento_status: 'confirmado', calendar_event_id: 'evt_1', etapa_prospect: 'agendado', agendado_em: Time.current)

      expect(perform).to eq(ok: false, reason: 'lead tem uma reunião confirmada')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'agendamento_falhou_callback')).to be_empty
    end
  end

  it 'remarcar (atualizar_evento) não vira callback' do
    expect(perform(ferramenta: 'atualizar_evento')).to eq(ok: false, reason: 'falha de atualizar_evento não vira callback')
    expect(lead.reload.agendamento_status).to eq('nao_iniciado')
  end
end
