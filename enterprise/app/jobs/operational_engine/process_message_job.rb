# Retry limitado e observável para mensagens que já foram aceitas pelo Chatwoot mas cuja escrita
# no Engine falhou. A idempotência no Supabase mantém as tentativas seguras (§5.5/§23.3).
class OperationalEngine::ProcessMessageJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: ->(executions) { executions * 15.seconds }, attempts: 3

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil?

    OperationalEngine::MessageProcessor.call(message)
  end
end
