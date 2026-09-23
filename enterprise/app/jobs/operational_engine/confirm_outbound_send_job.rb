# CP-02 (P0-019-01; SSOT §3.2 filas/retries controlados, §23.1, §23.3): o retry durável da
# confirmação de envio real. O listener tenta confirmar inline; se falhar (Supabase fora, lock
# ocupado, projeção quebrada...), enfileira este job pela `message_id` -- a transição
# source_id nil -> presente é efêmera e não se repete, então o retry não pode depender dela.
#
# Retries limitados e observáveis: backoff crescente, e ao esgotar a falha vai pro tracker (o
# OutboundConfirmationReconciler, no tick do dispatcher, ainda recupera o fato depois). O serviço é
# idempotente: reexecutar nunca duplica primeiro_contato_enviado/etapa_alterada.
module OperationalEngine
  class ConfirmOutboundSendJob < ApplicationJob
    MAX_ATTEMPTS = 5

    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
      Rails.logger.error("[OperationalEngine::ConfirmOutboundSendJob] esgotou retries message_id=#{job.arguments.first}: #{error.message}")
      ChatwootExceptionTracker.new(error).capture_exception
    end

    def perform(message_id)
      message = ::Message.find_by(id: message_id)
      return if message.nil? || message.source_id.blank? || !(message.outgoing? || message.template?)

      OperationalEngine::ConfirmOutboundSendService.call(message: message)
    end
  end
end
