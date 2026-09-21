# Resolução compartilhada de "qual lead esta chamada da Lavínia é sobre" (S-5): a Lavínia manda
# conversation_id (campo fixed no ToolDefinition, nunca escolhido pelo modelo -- ver I-3 do
# plano), não um lead_id direto. Mesmo caminho conversa->contato->telefone->lead do
# InboundProcessor, extraído aqui porque ScheduleMeetingService e RegisterCallbackService
# precisam dele igual -- divergir a lógica de tenant-scoping entre os dois seria o tipo de bug que
# não aparece em teste isolado.
module OperationalEngine
  module Tools
    class ResolveLeadFromConversation
      class NotFound < StandardError; end

      def self.call(...)
        new(...).call
      end

      def initialize(account:, conversation_id:)
        @account = account
        @conversation_id = conversation_id
      end

      def call
        # Escopado pela própria conta (não Conversation.find_by) -- garante que uma chave de uma
        # conta nunca resolve uma conversa de outra, mesmo que o conversation_id seja adivinhado.
        conversation = @account.conversations.find_by(id: @conversation_id)
        raise NotFound, 'conversa não encontrada' if conversation.blank?

        telefone = conversation.contact&.phone_number
        raise NotFound, 'contato sem telefone' if telefone.blank?

        lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: @account.id, telefone: telefone)
        raise NotFound, 'lead não encontrado para esta conversa' if lead.blank?

        lead
      end
    end
  end
end
