# CP-01 (P0-022-02, P0-024-01, P0-018-01; SSOT §12.4 "Engine revalida o estado imediatamente
# antes de qualquer envio", §23.2 "estado atual vence ação programada anteriormente").
#
# Autorização final Engine-controlled de TODA mensagem pública automática (AgentBot) numa conta
# com Operational Engine. Roda no ponto em que o post acontece de verdade -- a criação da Message
# pelo endpoint que o up2-agents chama com o token do bot (MessagesController#create, via overlay
# Enterprise) -- e não antes da geração no LLM. Vale pra qualquer caminho do up2-agents (resposta
# reativa, abertura do Dispatcher, nudge/follow-up, chunks de split): todos passam por aqui.
#
# Sem lock de banco durante LLM/rede: o lock de linha do lead (Supabase) é tomado só em volta da
# releitura + gravação local da Message (milissegundos). Como TakeoverService, ActivateDoNotContact
# e as demais mutações usam o MESMO lock, a ordem fica serializada: ou o fato novo entrou antes (e
# a mensagem é recusada), ou a mensagem já estava gravada antes dele.
#
# Regras, na ordem:
# 1. modo_atendimento=humano bloqueia (§12.4, §18.2, §23.2) -- exceto a resposta do próprio turno
#    que fez o handoff_comercial (decisão da Stéphanie em 23/09/2026, lacuna do SSOT registrada no
#    PR): dentro de HANDOFF_REPLY_WINDOW, sem mensagem humana depois e sem responsável humano --
#    exceto o responsável Comercial gravado pelo PRÓPRIO handoff (CP-16A, P2-VAL-16, 24/09/2026).
# 2. Conversa com ativação "authorized" e sem mensagem do contato = abertura do Dispatcher:
#    exige elegibilidade completa (OutboundEligibility) e nenhuma outra ativação já consumida.
# 3. Lead em Backlog sem ativação válida e sem mensagem do contato: abertura não autorizada.
# 1b. CP-06 (§18.3 "timers antigos não ressuscitam", RISK-026-01): envio programado do up2-agents
#    (carimbo `content_attributes.up2_automation.created_at` = quando o timer/job nasceu) criado
#    ANTES da última mudança de modo_atendimento é recusado -- um follow-up agendado antes do
#    Assumir não fala depois do Devolver. Carimbo presente mas ilegível falha fechado.
# 4. nao_contatar / cliente_atual / lead encerrado: só responde o contato (§19.1, §19.2, §28.26)
#    -- mensagem automática fora de REPLY_WINDOW desde a última mensagem dele é proativa
#    (timer/recovery/nudge/reativação) e é bloqueada.
# 5. CP-13 (P1-VAL-12; SSOT §15.6-§15.8, §28.4, §28.23, §28.25): post de RECOVERY (carimbo
#    up2_automation.kind=RECUPERACAO, job_id = activation_id) só sai com a RecoveryActivation
#    autorizada desta conversa/lead/tentativa E passando de novo por TODA a revalidação do §15.8
#    (RecoveryEligibility) sob o lock do lead, dentro da janela de recovery. O post consome a
#    ativação; balões da MESMA tentativa (split) passam dentro de opening_run_window.
# 6. CP-13: a recovery do SSOT é a ÚNICA automação de reengajamento numa conta com Engine. Post
#    programado do up2-agents (carimbo up2_automation) de um tipo fora da lista permitida
#    (ENV UP_SALES_ENGINE_AUTOMATION_KINDS, padrão APPOINTMENT_REMINDER) é recusado -- o follow-up
#    nativo (FOLLOWUP), o redirect de canal e qualquer tipo desconhecido não falam por fora do ciclo
#    do Engine (falha fechado).
#
# Falha fechado: se o Engine (Supabase) não responde, ou se o contato tem telefone mas nenhum lead
# é resolvido, a mensagem automática não sai (§23.3). Contato sem telefone fica fora do Engine.
module OperationalEngine
  class OutboundSendGate
    class Blocked < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super("envio automático bloqueado pelo Operational Engine: #{reason}")
      end
    end

    # Parâmetros técnicos (não regra de negócio), sobrescrevíveis por ENV.
    def self.reply_window
      ENV.fetch('UP_SALES_REPLY_WINDOW_MINUTES', '5').to_i.minutes
    end

    def self.handoff_reply_window
      OperationalEngine::HandoffReplyWindow.duration
    end

    # CP-02 (P0-022-01): quanto tempo depois de gravada a abertura ainda aceita balões da MESMA
    # abertura (split humanizado do up2-agents). Técnico, não regra de negócio.
    def self.opening_run_window
      ENV.fetch('UP_SALES_OPENING_RUN_WINDOW_SECONDS', '120').to_i.seconds
    end

    def self.applies?(conversation:, sender:, params:)
      return false unless sender.is_a?(::AgentBot)
      return false if ActiveModel::Type::Boolean.new.cast(params[:private])
      # template = mensagem aprovada do WhatsApp fora da janela de 24h: também é envio público.
      return false unless %w[outgoing template].include?((params[:message_type].presence || 'outgoing').to_s)

      UpSales::AgentTenant.exists?(account_id: conversation.account_id)
    end

    def self.authorize!(conversation:, params: {}, &)
      new(conversation, params).authorize!(&)
    end

    def initialize(conversation, params = {})
      @conversation = conversation
      @params = params
    end

    def authorize!
      return yield unless engine_tracked_contact?

      lead = find_lead
      # Contato com telefone numa conta com Engine e sem lead correspondente não é "fora do Engine":
      # é identidade não resolvida (ex.: telefone reescrito em outro formato -- RISK-019-02,
      # IP-01). Sem saber o estado do lead, a mensagem automática não sai.
      raise_blocked(nil, 'lead_nao_resolvido') if lead.nil?

      message = nil
      lead.with_lock do
        @conversation.reload
        activation = OperationalEngine::OriginationActivation.for(@conversation)
        recovery = OperationalEngine::RecoveryActivation.for(@conversation) if recovery_post?
        opening = !recovery_post? && opening?(lead, activation)

        reason = blocking_reason(lead, opening, activation, recovery)
        raise_blocked(lead, reason) if reason

        message = yield
        consume!(message, opening ? activation : nil, recovery)
      end
      message
    end

    private

    # Sem telefone (ex.: web widget) não existe lead possível -- a conversa fica fora do Engine.
    def engine_tracked_contact?
      @conversation.contact&.phone_number.present?
    end

    def find_lead
      OperationalEngine::LeadRepository.find_by_telefone(conta_id: @conversation.account_id, telefone: @conversation.contact.phone_number)
    rescue ActiveRecord::ActiveRecordError => e
      # Engine indisponível: não dá pra saber se o envio é permitido -- não envia.
      Rails.logger.error("[OperationalEngine::OutboundSendGate] engine indisponível: #{e.class}: #{e.message}")
      raise Blocked, 'engine_indisponivel'
    end

    def opening?(lead, activation)
      return false unless activation&.authorized? && activation.lead_id == lead.lead_id
      return true unless contact_spoke?

      # Resposta nova: o contato falou antes da abertura sair. A ativação deixa de valer; esta
      # mensagem passa a ser tratada como conversa (a abertura em si é barrada no up2-agents pelo
      # shouldPost da originação -- ver o PR coordenado).
      activation.transition!('superseded')
      false
    end

    def consume!(message, opening_activation, recovery)
      return unless message&.persisted?

      opening_activation&.transition!('consumed', message_id: message.id)
      recovery.transition!('consumed', message_id: message.id) if recovery&.authorized?
    end

    def blocking_reason(lead, opening, activation, recovery)
      return 'atendimento_humano' if human_block?(lead)

      automation_reason = automation_blocking_reason(lead, recovery)
      return automation_reason if automation_reason || recovery_post?

      conversation_blocking_reason(lead, opening, activation)
    end

    # Regras de envio PROGRAMADO (carimbo up2_automation): 1b, 5 e 6 do cabeçalho.
    def automation_blocking_reason(lead, recovery)
      return nil if automation_stamp.nil?
      return 'automacao_anterior_a_mudanca_de_modo' if stale_automation?(lead)

      automation_rules.blocking_reason(lead, recovery)
    end

    def automation_rules
      @automation_rules ||= OperationalEngine::AutomationSendRules.new(@conversation, automation_stamp)
    end

    def recovery_post?
      automation_rules.recovery?
    end

    def conversation_blocking_reason(lead, opening, activation)
      return opening_blocking_reason(lead) if opening
      # Abertura já gravada e contato ainda sem responder: balões da mesma abertura passam (dentro da
      # janela), reenvio não (CP-02) -- e as proteções proativas continuam valendo nos dois casos.
      return duplicate_opening_reason(activation) || proactive_blocking_reason(lead) if opening_run?(activation)
      return 'primeira_abordagem_sem_autorizacao' if unauthorized_opening?(lead)

      proactive_blocking_reason(lead)
    end

    def opening_run?(activation)
      activation&.status == 'consumed' && !contact_spoke?
    end

    # CP-02 (P0-022-01; §10.5 "uma única mensagem", §23.1): a abertura desta ativação já foi gravada e
    # o contato ainda não respondeu -- qualquer mensagem automática nova fora da janela da própria
    # abertura é um reenvio (retry/timeout/concorrência), não conversa. Recovery (Fase 7) terá a sua
    # própria autorização.
    def duplicate_opening_reason(activation)
      consumed_at = activation.status_at
      'abertura_ja_enviada' if consumed_at.nil? || consumed_at < self.class.opening_run_window.ago
    end

    def human_block?(lead)
      lead.modo_atendimento_humano? && !handoff_reply_allowed?(lead)
    end

    def stale_automation?(lead)
      stamp = automation_stamp
      return false if stamp.nil?

      created_at = Time.zone.parse(stamp['created_at'].to_s)
      return true if created_at.nil?

      lead.modo_atendimento_entrou_em.present? && created_at < lead.modo_atendimento_entrou_em
    rescue ArgumentError
      true
    end

    # content_attributes pode chegar como Hash ou como JSON em string (mesma tolerância do
    # Messages::MessageBuilder).
    def automation_stamp
      raw = @params[:content_attributes]
      raw = JSON.parse(raw) if raw.is_a?(String)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      stamp = raw.is_a?(Hash) ? raw.with_indifferent_access[:up2_automation] : nil
      stamp.is_a?(Hash) ? stamp.with_indifferent_access : nil
    rescue JSON::ParserError
      nil
    end

    def unauthorized_opening?(lead)
      lead.etapa_prospect_backlog? && !contact_spoke?
    end

    def proactive_blocking_reason(lead)
      protections = proactive_protections(lead)
      return nil if protections.empty? || within_reply_window?

      "contato_proativo_bloqueado:#{protections.join(',')}"
    end

    def opening_blocking_reason(lead)
      blockers = OperationalEngine::OutboundEligibility.origination_blockers(lead)
      blockers << 'ativacao_concorrente' if other_activation_consumed?
      blockers.presence&.join(',')
    end

    def proactive_protections(lead)
      [].tap do |protections|
        protections << 'nao_contatar' if lead.nao_contatar?
        protections << 'cliente_atual' if lead.relacao_atual == 'cliente_atual'
        protections << 'lead_encerrado' if lead.lead_status_encerrado?
      end
    end

    def contact_spoke?
      @conversation.messages.incoming.exists?
    end

    def within_reply_window?
      last_incoming_at = @conversation.messages.incoming.maximum(:created_at)
      last_incoming_at.present? && last_incoming_at >= self.class.reply_window.ago
    end

    # Outra conversa do mesmo contato já teve a abertura gravada (ainda que o provider não tenha
    # confirmado -- nesse intervalo primeiro_contato_em ainda é nil).
    def other_activation_consumed?
      ::Conversation.where(account_id: @conversation.account_id, contact_id: @conversation.contact_id)
                    .where.not(id: @conversation.id)
                    .exists?(["additional_attributes -> '#{OperationalEngine::OriginationActivation::KEY}' ->> 'status' = ?", 'consumed'])
    end

    # A resposta do turno que acabou de fazer handoff_comercial (decisão de 23/09/2026). A regra
    # inteira -- inclusive o responsável Comercial gravado pelo próprio handoff (CP-16A, P2-VAL-16,
    # decisão da Stéphanie em 24/09/2026) -- mora em OperationalEngine::HandoffReplyWindow, a mesma
    # que a ConversationModeProjection usa para não abrir a conversa antes dessa resposta.
    def handoff_reply_allowed?(lead)
      OperationalEngine::HandoffReplyWindow.new(lead, @conversation).open?
    end

    def raise_blocked(lead, reason)
      payload = { account_id: @conversation.account_id, conversation_id: @conversation.id, lead_id: lead&.lead_id, reason: reason }
      Rails.logger.warn("[OperationalEngine::OutboundSendGate] bloqueado #{payload.to_json}")
      raise Blocked, reason
    end
  end
end
