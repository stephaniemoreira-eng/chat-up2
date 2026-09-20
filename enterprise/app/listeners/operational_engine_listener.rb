# Fase 2 do Marco 1: registra a escuta dos eventos reais do Chatwoot e só loga. Decidir o que
# cada evento faz ao estado de um Lead (dedupe fino por source_id, auto-assume, etc.) é das
# fases seguintes -- ver OperationalEngine::EventWriter/IdempotencyGuard/LeadRepository, já
# prontos e testados, mas que este listener ainda não chama de propósito.
class OperationalEngineListener < BaseListener
  include Events::Types

  def message_created(event)
    message, account = extract_message_and_account(event)
    log('message_created', account_id: account.id, message_id: message.id)
  end

  def message_updated(event)
    message, account = extract_message_and_account(event)
    log('message_updated', account_id: account.id, message_id: message.id,
                            previous_changes: event.data[:previous_changes]&.keys)
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    log('assignee_changed', account_id: account.id, conversation_id: conversation.id)
  end

  private

  def log(event_name, **payload)
    Rails.logger.info("[OperationalEngine] #{event_name} #{payload.to_json}")
  end
end
