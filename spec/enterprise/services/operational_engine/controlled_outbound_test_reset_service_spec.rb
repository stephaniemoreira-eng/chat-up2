require 'rails_helper'

RSpec.describe OperationalEngine::ControlledOutboundTestResetService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:entrada_operacao_em) { 1.day.ago.change(usec: 0) }
  let(:lead) do
    OperationalEngine::Lead.create!(
      conta_id: account.id,
      telefone: contact.phone_number,
      upsales_contact_id: contact.id,
      modo_entrada: 'inbound',
      etapa_prospect: 'qualificado',
      lead_status: 'ativo',
      qualificacao_status: 'qualificado',
      recuperacao_status: 'ativa',
      tentativa_recuperacao: 2,
      proxima_recuperacao_em: 1.day.from_now,
      aguardando_resposta: true,
      agendamento_status: 'em_andamento',
      orcamento_status: 'personalizado',
      resultado_comercial: 'ganho',
      modo_atendimento: 'humano',
      frente_operacional: 'comercial',
      etapa_comercial: 'oportunidade',
      nao_contatar: true,
      propensao_fechamento: 'quente',
      motivo_handoff: 'excecao',
      entrada_operacao_em: entrada_operacao_em,
      primeiro_contato_em: 1.hour.ago,
      qualificado_em: 1.hour.ago,
      upsales_conversation_atual_id: 99
    )
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:old_conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
  end
  let(:recovery_conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          additional_attributes: OperationalEngine::RecoveryActivation.build_attributes(lead, tentativa: 1, canal: 'whatsapp'))
  end

  describe '.call' do
    it 'falha fechada quando a rotina não foi habilitada para homologação' do
      expect do
        described_class.call(lead: lead, reason: 'VAL-01')
      end.to raise_error(ArgumentError, /UP_SALES_TEST_RESET_ENABLED/)

      expect(OperationalEngine::OriginationActivation.for(old_conversation.reload)).to be_present
      expect(lead.reload.etapa_prospect).to eq('qualificado')
    end

    it 'remove ativações históricas do contato, preserva mensagens e audita o novo baseline' do
      old_message = create(:message, account: account, inbox: inbox, conversation: old_conversation, message_type: 'outgoing')
      other_contact = create(:contact, account: account, phone_number: '+5513999999999')
      unrelated = create(:conversation, account: account, inbox: inbox, contact: other_contact,
                                        additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))

      result = nil
      with_modified_env 'UP_SALES_TEST_RESET_ENABLED' => 'true' do
        result = described_class.call(lead: lead, reason: 'VAL-01 reteste 28.4')
      end

      expect(OperationalEngine::OriginationActivation.for(old_conversation.reload)).to be_nil
      expect(OperationalEngine::RecoveryActivation.for(recovery_conversation.reload)).to be_nil
      expect(OperationalEngine::OriginationActivation.for(unrelated.reload)).to be_present
      expect(old_conversation.messages.find_by(id: old_message.id)).to be_present
      expect(result.conversation_ids).to contain_exactly(old_conversation.id, recovery_conversation.id)

      lead.reload
      expect(lead.attributes.slice(*described_class::BASELINE_ATTRIBUTES.keys.map(&:to_s))).to include(
        'modo_entrada' => 'outbound', 'etapa_prospect' => 'backlog', 'lead_status' => 'ativo',
        'recuperacao_status' => 'inativa', 'tentativa_recuperacao' => 0, 'aguardando_resposta' => false,
        'modo_atendimento' => 'lavinia', 'frente_operacional' => 'prospeccao', 'nao_contatar' => false
      )
      expect(lead.etapa_entrou_em).to be_present
      expect(lead.entrada_operacao_em).to eq(entrada_operacao_em)

      event = OperationalEngine::LeadEvent.where(lead: lead, event_type: 'massa_teste_resetada').last
      expect(event.metadata).to include(
        'motivo' => 'VAL-01 reteste 28.4',
        'chaves_tecnicas_removidas' => described_class::ACTIVATION_KEYS,
        'conversas_limpas' => contain_exactly(old_conversation.id, recovery_conversation.id),
        'correlation_id' => result.correlation_id
      )
    end
  end
end
