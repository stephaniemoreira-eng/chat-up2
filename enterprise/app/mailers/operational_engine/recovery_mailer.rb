# CP-13 (P1-VAL-12; SSOT §15.3/§15.4 "tentativa 3: e-mail se disponível"): o e-mail da última
# tentativa de recovery.
#
# ActionMailer::Base direto (não ApplicationMailer) de propósito: ApplicationMailer engole as
# exceções SMTP (rescue_from ... handle_smtp_exceptions) -- aqui a falha TEM que subir, porque só um
# aceite real do relay conta como "enviado" (§23.3). raise_delivery_errors já é true no fork.
#
# Conteúdo: o SSOT e o Prompt V1.0 não definem o texto do e-mail (LACUNA registrada no PR). Modelo
# fixo e neutro -- só identidade e convite para continuar pelo WhatsApp, nenhuma afirmação comercial
# (preço, cobertura, prazo, certificação), então não conflita com a Base V0.7. Persona e marca são
# parâmetros (ENV UP_SALES_RECOVERY_EMAIL_PERSONA, padrão "Lavínia"; marca = nome da conta).
module OperationalEngine
  class RecoveryMailer < ActionMailer::Base
    default from: ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>')

    def follow_up
      @nome = params[:nome].to_s.strip.presence
      @marca = params[:marca].to_s.strip.presence || 'nossa equipe'
      @persona = ENV.fetch('UP_SALES_RECOVERY_EMAIL_PERSONA', 'Lavínia')

      mail(to: params[:to], subject: "#{@marca}: podemos continuar nossa conversa?") do |format|
        format.text { render plain: body_text }
      end
    end

    private

    def body_text
      <<~TEXT
        Olá#{", #{@nome}" if @nome}!

        Aqui é a #{@persona}, da #{@marca}. Tentei falar com você pelo WhatsApp e não quis deixar a nossa conversa se perder.

        Se fizer sentido para você, é só responder por lá quando puder.

        Um abraço,
        #{@persona} | #{@marca}
      TEXT
    end
  end
end
