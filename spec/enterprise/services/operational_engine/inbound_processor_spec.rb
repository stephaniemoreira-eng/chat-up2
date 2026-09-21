require 'rails_helper'

RSpec.describe OperationalEngine::InboundProcessor do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def build_message(**overrides)
    create(:message, conversation: conversation, account: account, message_type: 'incoming', **overrides)
  end

  it 'sem telefone no contato, nao faz nada (teste 28.6 nao se aplica)' do
    contact.update!(phone_number: nil)
    message = build_message

    expect { described_class.call(message: message) }.not_to change(OperationalEngine::Lead, :count)
  end

  describe 'lead novo (teste 28.6)' do
    it 'nasce direto em em_conversa, nunca em backlog/contatado' do
      message = build_message

      lead = described_class.call(message: message)

      expect(lead).to be_persisted
      expect(lead.etapa_prospect).to eq('em_conversa')
      expect(lead.entrada_operacao_em).to be_within(1.second).of(message.created_at)
    end

    it 'grava lead_criado, nova_entrada e etapa_alterada' do
      message = build_message

      lead = described_class.call(message: message)

      types = OperationalEngine::LeadEvent.where(lead: lead).pluck(:event_type)
      expect(types).to contain_exactly('lead_criado', 'nova_entrada', 'etapa_alterada')
    end

    it 'usa inbound_direto como origem e marca a inbox de entrada e atual' do
      message = build_message

      lead = described_class.call(message: message)

      expect(lead.origem_lead).to eq('inbound_direto')
      expect(lead.inbox_entrada_id).to eq(conversation.inbox_id)
      expect(lead.inbox_atual_id).to eq(conversation.inbox_id)
    end

    it 'nao duplica lead pro mesmo telefone processado duas vezes (teste 28.9 aplicado ao inbound)' do
      message = build_message

      described_class.call(message: message)

      expect { described_class.call(message: message) }.not_to change(OperationalEngine::Lead, :count)
    end

    it 'cria a projecao Sales::Lead' do
      message = build_message

      described_class.call(message: message)

      expect(Sales::Lead.find_by(account_id: account.id, contact_id: contact.id)).to be_present
    end
  end

  describe 'lead existente (teste 28.8)' do
    let!(:lead) do
      OperationalEngine::LeadRepository.find_or_create_by_telefone(
        conta_id: account.id, telefone: contact.phone_number,
        attributes: { origem_lead: 'google_ads', inbox_entrada_id: 999, inbox_atual_id: 999, upsales_contact_id: contact.id }
      )
    end

    it 'nao cria um segundo lead' do
      message = build_message

      expect { described_class.call(message: message) }.not_to change(OperationalEngine::Lead, :count)
    end

    it 'preserva origem_lead original mesmo mensagem chegando por outra inbox' do
      message = build_message

      described_class.call(message: message)

      expect(lead.reload.origem_lead).to eq('google_ads')
    end

    it 'atualiza inbox_atual_id quando a mensagem chega por uma inbox diferente, e registra nova_entrada' do
      message = build_message

      described_class.call(message: message)

      expect(lead.reload.inbox_atual_id).to eq(conversation.inbox_id)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'nova_entrada').count).to eq(1)
    end

    it 'na mesma inbox de sempre, so atualiza ultima_interacao_em sem gravar evento' do
      lead.update!(inbox_atual_id: conversation.inbox_id)
      message = build_message

      expect { described_class.call(message: message) }.not_to change(OperationalEngine::LeadEvent, :count)
      expect(lead.reload.ultima_interacao_em).to be_within(1.second).of(message.created_at)
    end

    it 'tambem sincroniza o card Comercial (Fase 9) quando o lead ja e uma oportunidade' do
      lead.update!(etapa_comercial: 'oportunidade')
      message = build_message

      described_class.call(message: message)

      comercial_card = Sales::Lead.joins(:pipeline).find_by(contact_id: contact.id, sales_pipelines: { engine_kind: 'comercial' })
      expect(comercial_card).to be_present
    end
  end
end
