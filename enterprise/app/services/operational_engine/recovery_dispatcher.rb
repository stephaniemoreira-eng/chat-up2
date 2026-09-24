# CP-13 (P1-VAL-12; SSOT §15.5-§15.8, §23.1-§23.3): a metade Recovery do dispatcher. Roda no mesmo
# tick do DispatcherJob, DEPOIS da primeira abordagem, e usa a MESMA fila de saída por inbox
# (§15.6): o espaçamento é o DispatchPacing, que conta tanto aberturas quanto tentativas de recovery
# na inbox -- nunca duas mensagens automáticas na mesma inbox dentro do intervalo, e um tick
# atrasado nunca compensa com rajada (a referência é sempre a última tentativa real).
#
# - Recovery NÃO consome o limite de 20 novas ativações (§15.6): BacklogCapacity conta só
#   primeiro_contato_em; nada aqui toca nisso.
# - Janela (§15.5): só age dentro de seg-sex 09:00-18:00 America/Sao_Paulo (RecoveryCalendar).
# - Prioridade (§15.7): RecoverySelector (conversava e parou antes de nunca respondeu; FIFO).
# - Ordem primeira abordagem × recovery no mesmo tick: LACUNA do SSOT; decisão registrada -- a
#   abertura vai primeiro (a janela de novas ativações é a mais estreita, 2x2h; a de recovery é 9h).
# - Revalidação (§15.8) sob o lock do lead ANTES de autorizar, e de novo no post (OutboundSendGate).
# - Preserva itens (§15.6): sem vaga de pacing/teto, o lead só fica para o próximo tick.
# - Nunca segura lock durante LLM/rede/SMTP (mesmo desenho do Dispatcher).
module OperationalEngine
  class RecoveryDispatcher
    # E-mail não passa pela fila WhatsApp da inbox, mas também não sai em rajada.
    EMAILS_POR_TICK = 1

    def self.call(conta_id:, now: Time.current)
      new(conta_id, now).call
    end

    def initialize(conta_id, now)
      @conta_id = conta_id
      @now = now
      @emails = 0
    end

    def call
      return unless agent_tenant&.dispatcher_ready?
      return unless OperationalEngine::RecoveryCalendar.within_window?(@now)

      OperationalEngine::RecoverySelector.vencidos(conta_id: @conta_id, agora: @now).each { |lead| process(lead) }
    end

    private

    def agent_tenant
      @agent_tenant ||= UpSales::AgentTenant.find_by(account_id: @conta_id)
    end

    def process(lead)
      step = prepare(lead)
      return if step.nil?

      step[:canal] == 'email' ? dispatch_email(lead, step) : dispatch_whatsapp(lead, step)
    rescue StandardError => e
      Rails.logger.error("[OperationalEngine::RecoveryDispatcher] lead=#{lead.lead_id}: #{e.class}: #{e.message}")
      ChatwootExceptionTracker.new(e, account: agent_tenant.account).capture_exception
    end

    # Sob o lock do lead: relê, revalida §15.8, inicia o ciclo ou esgota. Devolve o passo a executar.
    def prepare(lead)
      conversation = OperationalEngine::RecoveryEligibility.conversation_for(lead)
      step = nil
      lead.with_lock do
        next unless lead.proxima_recuperacao_em.present? && lead.proxima_recuperacao_em <= @now

        step = next_step(lead, conversation)
      end
      OperationalEngine::ProjectionReconciler.flush(lead)
      step
    end

    def next_step(lead, conversation)
      blockers = OperationalEngine::RecoveryEligibility.blockers(lead, conversation: conversation, agent_tenant: agent_tenant)
      if blockers.any?
        OperationalEngine::RecoveryCycle.interrupt!(lead, blockers)
        return nil
      end

      tentativa = lead.tentativa_recuperacao + 1
      if tentativa > OperationalEngine::RecoveryCadence::MAX_TENTATIVAS
        OperationalEngine::RecoveryCycle.exhaust!(lead)
        return nil
      end

      OperationalEngine::RecoveryCycle.start!(lead, conversation) unless lead.recuperacao_status_ativa?
      { tentativa: tentativa, canal: OperationalEngine::RecoveryCadence.canal(tentativa), conversation: conversation }
    end

    def dispatch_whatsapp(lead, step)
      conversation = step[:conversation]
      return unless OperationalEngine::DispatchPacing.allows?(inbox_id: conversation.inbox_id, now: @now)
      return if daily_limit_reached?

      activation, estado = OperationalEngine::RecoveryActivation.authorize!(conversation, lead, tentativa: step[:tentativa], canal: 'whatsapp')
      return interrupt_after_failures(lead, step) if estado == :esgotada
      return unless estado == :ok && activation.claim_attempt!(@now)

      UpSales::Agents::RecoverConversationService.new(agent_tenant: agent_tenant, conversation: conversation, activation: activation).perform
    rescue UpSales::Agents::RecoverConversationService::SyncError => e
      record_failure(lead, activation, e.message)
    end

    def dispatch_email(lead, step)
      return if @emails >= EMAILS_POR_TICK || daily_limit_reached?

      address = OperationalEngine::RecoveryEmail.address_for(lead, step[:conversation])
      return skip_email(lead, 'email_indisponivel') if address.nil?
      return skip_email(lead, 'canal_email_nao_configurado') unless OperationalEngine::RecoveryEmail.channel_configured?

      activation, estado = OperationalEngine::RecoveryActivation.authorize!(step[:conversation], lead, tentativa: step[:tentativa], canal: 'email')
      case estado
      when :esgotada then skip_email(lead, 'email_falhou')
      when :consumida then confirm_email(lead, activation)
      when :ok then send_email(lead, activation, address)
      end
    end

    def send_email(lead, activation, address)
      return unless activation.claim_attempt!(@now)

      @emails += 1
      message_id = OperationalEngine::RecoveryEmail.deliver!(lead: lead, address: address, account: agent_tenant.account)
      activation.transition!('consumed', email_message_id: message_id)
      confirm_email(lead, activation)
    rescue OperationalEngine::RecoveryEmail::DeliveryError => e
      record_failure(lead, activation, e.message)
    end

    def confirm_email(lead, activation)
      lead.with_lock { OperationalEngine::RecoveryCycle.confirm_email!(lead, activation) }
      activation.transition!('confirmed')
      OperationalEngine::ProjectionReconciler.flush(lead)
    end

    # "Se não houver e-mail, pular a ação de e-mail sem inventar dado" -- a tentativa 3 não acontece e
    # o ciclo esgota (a espera da tentativa 3 já transcorreu: só chegamos aqui quando ela venceu).
    def skip_email(lead, motivo)
      lead.with_lock do
        next unless lead.recuperacao_status_ativa? && lead.tentativa_recuperacao == OperationalEngine::RecoveryCadence::MAX_TENTATIVAS - 1

        OperationalEngine::RecoveryCycle.exhaust!(lead, tentativa_pulada: OperationalEngine::RecoveryCadence::MAX_TENTATIVAS,
                                                        canal_pulado: 'email', motivo_pulo: motivo)
      end
      OperationalEngine::ProjectionReconciler.flush(lead)
    end

    # §23.3 "retries limitados e observáveis": cada falha vira evento com o número da tentativa
    # técnica; ao esgotar, a ativação vira failed e o próximo tick interrompe o ciclo.
    def record_failure(lead, activation, motivo)
      terminal = activation.attempts >= OperationalEngine::RecoveryActivation::MAX_ATTEMPTS
      activation.transition!('failed', motivo: motivo) if terminal
      Rails.logger.error("[OperationalEngine::RecoveryDispatcher] tentativa #{activation.tentativa} falhou lead=#{lead.lead_id} " \
                         "(execução #{activation.attempts}#{', terminal' if terminal}): #{motivo}")
      OperationalEngine::LeadEvent.create!(
        lead: lead, event_type: 'recuperacao_envio_falhou', source: 'system', event_at: Time.current,
        metadata: { tentativa: activation.tentativa, canal: activation.canal, execucao: activation.attempts, terminal: terminal,
                    motivo: motivo.to_s.first(500), activation_id: activation.activation_id, correlation_id: SecureRandom.uuid }
      )
    end

    def interrupt_after_failures(lead, step)
      lead.with_lock do
        next unless lead.recuperacao_status_ativa? && lead.tentativa_recuperacao == step[:tentativa] - 1

        OperationalEngine::RecoveryCycle.interrupt!(lead, ['falha_tecnica_persistente'])
      end
      OperationalEngine::ProjectionReconciler.flush(lead)
    end

    # §25 limite_recuperacoes_dia (vazio = sem teto). Conta tentativas CONFIRMADAS hoje (SP).
    def daily_limit_reached?
      limit = OperationalEngine::RecoveryCadence.daily_limit
      return false if limit.nil?

      day = @now.in_time_zone(OperationalEngine::RecoveryCalendar::TIMEZONE)
      OperationalEngine::LeadEvent.joins(:lead)
                                  .where(leads: { conta_id: @conta_id })
                                  .where(event_type: %w[recuperacao_mensagem_enviada recuperacao_email_enviado])
                                  .where(event_at: day.beginning_of_day..day.end_of_day)
                                  .count >= limit
    end
  end
end
