# Fase 3 do Marco 1: message_created agora aciona de fato o Engine (inbound + auto-assume, §11 e
# §18.2). message_updated e assignee_changed continuam só logando -- confirmação de envio real
# (source_id) é Fase 6, e ASSIGNEE_CHANGED nativo do Chatwoot não é o gatilho do Assumir/Devolver
# do SSOT (esse é por mensagem pública humana, não por reatribuição de conversa).
#
# Nunca deixa uma falha aqui derrubar o dispatch: um bug no Engine não pode impedir o Chatwoot de
# salvar a mensagem que disparou o evento (mesmo padrão de Reporting::EventListener).
class OperationalEngineListener < BaseListener
  include Events::Types

  def message_created(event)
    message, account = extract_message_and_account(event)

    if message.incoming?
      OperationalEngine::InboundProcessor.call(message: message)
    elsif message.human_response? && !message.private?
      auto_assumir(message, account)
    end

    log('message_created', account_id: account.id, message_id: message.id)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
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

  # §18.2: "mensagem pública humana deve auto-assumir". O lead precisa já existir -- uma resposta
  # nossa pressupõe uma conversa que já tem um lead por trás (criado pelo inbound, ou por outro
  # caminho fora de Fase 3); não fabricamos um lead a partir só de uma mensagem de saída.
  def auto_assumir(message, account)
    phone = message.conversation.contact&.phone_number
    return if phone.blank?

    lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: account.id, telefone: phone)
    return if lead.nil?

    OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: message.sender_id)
  end

  def log(event_name, **payload)
    Rails.logger.info("[OperationalEngine] #{event_name} #{payload.to_json}")
  end
end
