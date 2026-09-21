require 'rails_helper'

RSpec.describe OperationalEngine::Tools::RegisterCallbackService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number) }

  def perform
    described_class.new(account: account, conversation_id: conversation.id).call
  end

  it 'retorna erro quando a conversa não existe' do
    result = described_class.new(account: account, conversation_id: -1).call

    expect(result).to eq(ok: false, reason: 'conversa não encontrada')
  end

  it 'registra o callback e abre oportunidade Comercial' do
    result = perform

    expect(result).to eq(ok: true)
    lead.reload
    expect(lead.agendamento_status).to eq('callback_registrado')
    expect(lead.etapa_comercial).to eq('oportunidade')
  end

  it 'não é conversão -- nunca toca conversao_em/tipo_conversao' do
    perform

    lead.reload
    expect(lead.conversao_em).to be_nil
    expect(lead.tipo_conversao).to be_nil
  end

  it 'não rebaixa uma oportunidade que já avançou' do
    lead.update!(etapa_comercial: 'ganho')

    perform

    expect(lead.reload.etapa_comercial).to eq('ganho')
  end

  it 'grava o evento callback_registrado' do
    perform

    event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'callback_registrado')
    expect(event).to be_present
    expect(event.source).to eq('lavinia')
  end

  it 'sincroniza a tag CALLBACK no card Prospect e cria o card Comercial' do
    perform

    sales_lead = Sales::Lead.find_by(contact_id: contact.id)
    expect(sales_lead.custom_attributes['engine_tags']).to include('callback')

    comercial_card = Sales::Lead.joins(:pipeline).find_by(contact_id: contact.id, sales_pipelines: { engine_kind: 'comercial' })
    expect(comercial_card).to be_present
  end
end
