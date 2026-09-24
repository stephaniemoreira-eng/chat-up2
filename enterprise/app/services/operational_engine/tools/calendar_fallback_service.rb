# CP-16B (P2-VAL-19; SSOT §16.1, §16.2, §23.1, §28.15, §28.16). Decisão da Stéphanie em 24/09/2026:
#
#   "SE FALHAR, AGUARDAR E TENTAR MAIS UMA VEZ EM SILÊNCIO, COM MAIS UMA FALHA > MENSAGEM DE QUE O
#    DANILO VAI ENTRAR EM CONTATO EM BREVE E REGISTRAR NO CAMPO COMO CALLBACK DANILO."
#
# O desfecho da SEGUNDA falha do Calendar ao agendar (`criar_evento`), pedido pelo up2-agents depois
# de esgotar as duas tentativas (OperationalEngine::CalendarRetryAttempt):
#
# 1. registra o callback pelo MESMO caminho do "registrar callback" (RegisterCallbackService, CP-09:
#    Prospect Qualificado + CALLBACK, oportunidade Comercial), com a origem explícita no evento
#    (motivo `falha_calendar`, origem `criar_evento`) e o responsável Comercial que a conta tiver --
#    resolvido SÓ por OperationalEngine::CommercialResponsibleResolver (o CP-16A é quem define a
#    configuração por conta; aqui não há segunda regra). Sem responsável configurado, o callback fica
#    registrado com `responsavel_pendente: true` e um humano o assume pelo card, como no handoff.
#    O responsável vai no evento, NÃO em `responsavel_atual_id`: callback não é handoff (CP-09) -- o
#    lead continua com a Lavínia, e gravar um humano ali mudaria o gate de envio;
# 2. devolve o texto FIXO que o up2-agents envia ao lead no lugar da resposta do modelo (o Prompt V1.0
#    é controlado e não pode ganhar instrução nova -- o texto é configuração, não prompt). Ele passa
#    pelo OutboundSendGate como qualquer post da Lavínia: modo humano / não-contatar continuam barrando.
#    O texto nunca diz "agendado" (28.15): um texto configurado que diga é trocado pelo padrão.
#
# Guardas: as do próprio RegisterCallbackService (modo humano, não-contatar, encerrado, não qualificado,
# reunião confirmada). Recusado => nenhuma mensagem sai (o up2-agents só envia com ok:true) e o turno
# termina em silêncio + nota privada, como antes do CP-16B.
#
# Remarcar (`atualizar_evento`) NÃO tem este desfecho -- ver o comentário de FERRAMENTAS abaixo.
# Idempotência: o controller envolve esta chamada no ledger do turno (`ferramenta:fallback_calendar`
# + turn_id) -- repetir não duplica callback, evento nem mensagem.
module OperationalEngine
  module Tools
    class CalendarFallbackService
      MOTIVO = 'falha_calendar'.freeze
      # Só "Criar evento". Remarcar falhando duas vezes deixa a reunião ANTIGA confirmada no Calendar
      # (fato real): gravar callback_registrado por cima apagaria esse fato (o CP-09 recusa callback
      # com reunião confirmada) e prometer "o Danilo entra em contato" sem nada registrado seria
      # prometer sem dono -- remarcar fica com a 2ª tentativa silenciosa + o silêncio/nota do 28.15.
      # Cancelar não tem nem a 2ª tentativa (decisão registrada no PR do CP-16B).
      FERRAMENTAS = %w[criar_evento].freeze
      DEFAULT_MESSAGE = 'O Danilo vai entrar em contato com você em breve para combinarmos o melhor horário.'.freeze
      ACCOUNT_MESSAGE_KEY = 'up_sales_calendar_fallback_message'.freeze
      FORBIDDEN_WORDING = /agendad|confirmad|marcad/i

      # Texto fixo configurável: por conta (Account#custom_attributes[ACCOUNT_MESSAGE_KEY]) >
      # ENV UP_SALES_CALENDAR_FALLBACK_MESSAGE > padrão fiel à decisão.
      def self.message_for(account)
        configured = account.custom_attributes.to_h[ACCOUNT_MESSAGE_KEY].presence || ENV['UP_SALES_CALENDAR_FALLBACK_MESSAGE'].presence
        return DEFAULT_MESSAGE if configured.blank? || configured.to_s.match?(FORBIDDEN_WORDING)

        configured.to_s.strip
      end

      def initialize(account:, conversation_id:, ferramenta:)
        @account = account
        @conversation_id = conversation_id
        @ferramenta = ferramenta.to_s
      end

      def call
        return { ok: false, reason: "falha de #{@ferramenta.presence || 'ferramenta'} não vira callback" } unless FERRAMENTAS.include?(@ferramenta)

        lead = OperationalEngine::Tools::ResolveLeadFromConversation.call(account: @account, conversation_id: @conversation_id)
        responsavel_id = OperationalEngine::CommercialResponsibleResolver.call(lead: lead)
        callback = register_callback(responsavel_id)
        return callback unless callback[:ok]

        record_fallback(lead, responsavel_id)
        { ok: true, callback: 'registrado', motivo: MOTIVO, responsavel_comercial_id: responsavel_id,
          responsavel_pendente: responsavel_id.nil?, mensagem_lead: self.class.message_for(@account) }
      rescue OperationalEngine::Tools::ResolveLeadFromConversation::NotFound => e
        { ok: false, reason: e.message }
      end

      private

      def register_callback(responsavel_id)
        OperationalEngine::Tools::RegisterCallbackService.new(
          account: @account, conversation_id: @conversation_id,
          motivo: MOTIVO, origem: @ferramenta, responsavel_comercial_id: responsavel_id
        ).call
      end

      # Trilha própria da falha dupla, mesmo quando o callback já existia (RegisterCallbackService é
      # no-op nesse caso e não grava evento novo): a timeline mostra por que a Lavínia prometeu o contato.
      def record_fallback(lead, responsavel_id)
        OperationalEngine::LeadEvent.create!(
          lead: lead, event_type: 'agendamento_falhou_callback', source: 'lavinia',
          metadata: { motivo: MOTIVO, ferramenta: @ferramenta, tentativas: OperationalEngine::CalendarRetryAttempt::SEGUNDA_TENTATIVA,
                      responsavel_comercial_id: responsavel_id, correlation_id: SecureRandom.uuid }
        )
      end
    end
  end
end
