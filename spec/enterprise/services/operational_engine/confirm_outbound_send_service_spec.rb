require 'rails_helper'

RSpec.describe OperationalEngine::ConfirmOutboundSendService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def perform(message)
    described_class.call(message: message)
  end

  context 'lead nasceu no Backlog (outbound, §10.5)' do
    let!(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog')
    end

    it 'confirma o primeiro contato e move pra contatado' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)

      lead.reload
      expect(lead.primeiro_contato_em).to be_present
      expect(lead.etapa_prospect).to eq('contatado')
      expect(lead.etapa_entrou_em).to be_present
    end

    it 'grava o evento primeiro_contato_enviado' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)

      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'primeiro_contato_enviado')
      expect(event).to be_present
      expect(event.metadata['source_id']).to eq('wamid.abc')
    end

    it 'é idempotente -- não regride etapa_prospect nem duplica evento numa segunda confirmação' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)
      lead.update!(etapa_prospect: 'em_conversa') # avançou depois -- confirmação repetida não pode voltar
      perform(message)

      expect(lead.reload.etapa_prospect).to eq('em_conversa')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'primeiro_contato_enviado').count).to eq(1)
    end
  end

  context 'lead nasceu inbound (já em em_conversa, nunca passou por backlog)' do
    let!(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa')
    end

    it 'confirma o primeiro contato sem mexer em etapa_prospect' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

      perform(message)

      lead.reload
      expect(lead.primeiro_contato_em).to be_present
      expect(lead.etapa_prospect).to eq('em_conversa')
    end
  end

  it 'não faz nada quando não existe lead pra este telefone' do
    outro_contact = create(:contact, account: account, phone_number: '+5513999999999')
    outra_conversa = create(:conversation, account: account, contact: outro_contact)
    message = create(:message, conversation: outra_conversa, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

    expect { perform(message) }.not_to raise_error
  end

  it 'não faz nada quando o contato não tem telefone' do
    sem_telefone = create(:contact, account: account, phone_number: nil)
    conversa_sem_telefone = create(:conversation, account: account, contact: sem_telefone)
    message = create(:message, conversation: conversa_sem_telefone, account: account, message_type: 'outgoing', source_id: 'wamid.abc')

    expect { perform(message) }.not_to raise_error
  end

  # CP-02 -- P1-019-01, P1-019-02, P0-019-01, P2-019-01 (SSOT §9, §10.6, §28.1).
  describe 'confirmação operacional completa e recuperável' do
    let!(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog',
                                      upsales_contact_id: contact.id)
    end
    let(:message) { create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.abc') }

    it 'outbound confirmado grava entrada_operacao_em, primeiro_contato_em e etapa_entrou_em no mesmo instante (§28.1)' do
      perform(message)

      lead.reload
      expect(lead.entrada_operacao_em).to be_present
      expect(lead.entrada_operacao_em).to eq(lead.primeiro_contato_em)
      expect(lead.etapa_entrou_em).to eq(lead.primeiro_contato_em)
    end

    it 'Backlog -> Contatado grava exatamente um etapa_alterada com de/para/motivo' do
      2.times { perform(message) }

      events = OperationalEngine::LeadEvent.where(lead: lead, event_type: 'etapa_alterada')
      expect(events.count).to eq(1)
      expect(events.first.metadata).to include('de' => 'backlog', 'para' => 'contatado', 'motivo' => 'primeiro_contato_enviado')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'primeiro_contato_enviado').count).to eq(1)
    end

    it 'reprocessamento não altera entrada_operacao_em' do
      perform(message)
      original = lead.reload.entrada_operacao_em

      travel(1.hour) { perform(message) }

      expect(lead.reload.entrada_operacao_em).to eq(original)
    end

    it 'falha transitória antes da persistência: nova tentativa recupera o fato sem nova transição de source_id' do
      allow(OperationalEngine::LeadRepository).to receive(:find_by_telefone).and_raise(ActiveRecord::ConnectionNotEstablished)
      expect { perform(message) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      expect(lead.reload.primeiro_contato_em).to be_nil

      allow(OperationalEngine::LeadRepository).to receive(:find_by_telefone).and_call_original
      OperationalEngine::ConfirmOutboundSendJob.perform_now(message.id)

      expect(lead.reload.etapa_prospect).to eq('contatado')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'primeiro_contato_enviado').count).to eq(1)
    end

    it 'falha só na projeção: o retry repara o CRM sem recriar o evento de negócio' do
      allow(OperationalEngine::SalesProjectionSync).to receive(:call).and_raise('CRM fora')
      expect { perform(message) }.to raise_error('CRM fora')
      expect(lead.reload.primeiro_contato_em).to be_present

      allow(OperationalEngine::SalesProjectionSync).to receive(:call).and_call_original
      perform(message)

      expect(Sales::Lead.find_by(contact_id: contact.id)&.stage&.engine_stage_key).to eq('contatado')
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'primeiro_contato_enviado').count).to eq(1)
    end
  end

  it 'lead inbound: primeiro envio outbound não sobrescreve entrada_operacao_em nem gera etapa_alterada falso' do
    original = 2.days.ago.change(usec: 0)
    lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa',
                                           entrada_operacao_em: original)
    message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', source_id: 'wamid.in')

    perform(message)

    expect(lead.reload.entrada_operacao_em).to eq(original)
    expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'etapa_alterada')).to be_empty
  end
end
