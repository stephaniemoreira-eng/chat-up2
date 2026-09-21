# Processa uma mensagem já persistida pelo Chatwoot. Separar esta unidade do listener permite
# reexecutá-la por job sem redispatch do evento nativo, preservando a garantia de que uma falha
# temporária do Engine não perde o fato de negócio (§4/§23.3).
module OperationalEngine
  class MessageProcessor
    def self.call(message)
      new(message).call
    end

    def initialize(message)
      @message = message
      @account = message.account
    end

    def call
      if @message.incoming?
        OperationalEngine::InboundProcessor.call(message: @message)
      elsif @message.send(:human_response?) && !@message.private?
        assumir_conversa
      end
    end

    private

    def assumir_conversa
      phone = @message.conversation.contact&.phone_number
      return if phone.blank?

      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: @account.id, telefone: phone)
      return if lead.nil?

      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: @message.sender_id)
    end
  end
end
