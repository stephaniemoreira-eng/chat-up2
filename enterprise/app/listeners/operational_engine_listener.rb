# Fase 3 do Marco 1: message_created aciona o Engine (inbound + auto-assume, §11 e §18.2).
# message_updated agora também aciona -- confirmação de envio real via source_id (§10.6, Fase 6,
# S-7) -- e assignee_changed continua só logando: ASSIGNEE_CHANGED nativo do Chatwoot não é o
# gatilho do Assumir/Devolver do SSOT (esse é por mensagem pública humana, não por reatribuição de
# conversa).
#
# Nunca deixa uma falha aqui derrubar o dispatch: um bug no Engine não pode impedir o Chatwoot de
# salvar a mensagem que disparou o evento (mesmo padrão de Reporting::EventListener).
class OperationalEngineListener < BaseListener
  include Events::Types

  def message_created(event)
    message, account = extract_message_and_account(event)

    if message.incoming?
      OperationalEngine::InboundProcessor.call(message: message)
    # human_response? is private on Message (native, not ours to change per ADR-0001) -- `send`
    # is the deliberate bridge, not an oversight. Confirmed here the hard way: calling it with an
    # explicit receiver raises NoMethodError, which this method's own rescue below was silently
    # swallowing, masking the bug as "auto-assume just didn't happen".
    elsif message.send(:human_response?) && !message.private?
      auto_assumir(message, account)
    end

    log('message_created', account_id: account.id, message_id: message.id)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  def message_updated(event)
    message, account = extract_message_and_account(event)
    previous_changes = event.data[:previous_changes] || {}

    confirm_outbound_send(message, account) if source_id_just_confirmed?(message, previous_changes)

    log('message_updated', account_id: account.id, message_id: message.id, previous_changes: previous_changes.keys)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
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

  # CP-02 (P0-019-01): a transição source_id nil -> presente acontece UMA vez. Confirmar inline é o
  # caminho rápido; se falhar, o fato não pode se perder -- vai pro ConfirmOutboundSendJob (retry
  # durável por message_id) e, em último caso, o OutboundConfirmationReconciler recupera no tick.
  def confirm_outbound_send(message, account)
    OperationalEngine::ConfirmOutboundSendService.call(message: message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    OperationalEngine::ConfirmOutboundSendJob.set(wait: 30.seconds).perform_later(message.id)
  end

  # Risco §14.1 do plano: só a transição de branco pra presente confirma o envio real -- não
  # basta source_id estar presente agora (isso é verdade em qualquer message_updated depois do
  # primeiro), e mensagem de atividade/nota do sistema nunca passa por aqui, mesmo que ganhe
  # algum id por outro motivo.
  def source_id_just_confirmed?(message, previous_changes)
    return false unless message.outgoing? || message.template?

    old_value, new_value = previous_changes['source_id']
    old_value.blank? && new_value.present?
  end

  def log(event_name, **payload)
    Rails.logger.info("[OperationalEngine] #{event_name} #{payload.to_json}")
  end
end
