# CP-13 (P1-VAL-12; SSOT §15.3/§15.4): o canal e-mail da tentativa 3 -- "e-mail se disponível; se
# não houver e-mail, pular a ação de e-mail sem inventar dado".
#
# Disponível = existe um endereço sintaticamente válido no lead (Engine, `email`) ou, na falta, no
# contato da conversa do ciclo -- nada é inferido/derivado -- E o fork tem um canal de envio real
# configurado (SMTP relay ou Resend; sem SMTP_ADDRESS o Rails cai em :sendmail, que não existe no
# container -- tratado como canal indisponível).
#
# "Enviado com sucesso" (decisão registrada): o relay aceitou a mensagem (deliver_now sem exceção,
# com raise_delivery_errors=true). Bounce/entrega final são assíncronos e não observáveis aqui --
# LACUNA/risco residual. O endereço nunca vai para log nem para lead_events (só o Message-ID).
module OperationalEngine
  class RecoveryEmail
    class DeliveryError < StandardError; end

    UNAVAILABLE_DELIVERY_METHODS = %i[sendmail].freeze

    def self.address_for(lead, conversation)
      [lead.email, conversation&.contact&.email].map { |value| value.to_s.strip }
                                                .find { |value| value.match?(URI::MailTo::EMAIL_REGEXP) }
    end

    def self.channel_configured?
      ActionMailer::Base.perform_deliveries && UNAVAILABLE_DELIVERY_METHODS.exclude?(ActionMailer::Base.delivery_method)
    end

    # Algo com cara de endereço dentro de uma mensagem de erro SMTP (ex.: "550 <x@y> user unknown").
    ADDRESS_IN_TEXT = /[^\s<>"'@]+@[^\s<>"'@]+/

    # Devolve o Message-ID do e-mail aceito.
    #
    # CP-16A (P2-VAL-17; Stéphanie, 24/09/2026: texto "SER AJUSTÁVEL"): assunto/corpo configurados na
    # conta (UpSales::AgentTenant) seguem para o mailer; vazios = modelo neutro do CP-13. A mensagem da
    # falha tem endereços mascarados -- ela vai para o registro de falha da ativação/log.
    def self.deliver!(lead:, address:, account:)
      tenant = account&.up_sales_agent_tenant
      mail = OperationalEngine::RecoveryMailer.with(
        to: address, nome: lead.nome, empresa: lead.empresa, marca: account&.name,
        subject_template: tenant&.recovery_email_subject, body_template: tenant&.recovery_email_body
      ).follow_up.deliver_now
      mail.message_id
    rescue StandardError => e
      raise DeliveryError, "#{e.class}: #{e.message.to_s.gsub(ADDRESS_IN_TEXT, '[email]')}"
    end
  end
end
