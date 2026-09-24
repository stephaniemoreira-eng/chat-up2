# CP-13 (P1-VAL-12; SSOT §15.6, §15.8, §23.1, §23.2): a autorização Engine-controlled de UMA
# tentativa de recovery -- o equivalente da OriginationActivation (CP-01/CP-02) para o Recovery, e
# que reutiliza a mesma mecânica (claim com lease, MAX_ATTEMPTS, transições sob o lock da conversa).
#
# Gravada pelo RecoveryDispatcher na conversa do ciclo (conversations.additional_attributes, estado
# técnico de coordenação -- §23.1 permite que ele viva no UpSales). O OutboundSendGate só aceita um
# post de recovery (carimbo up2_automation.kind=RECUPERACAO + job_id = activation_id) se esta
# ativação ainda estiver autorizada E o lead passar de novo por toda a revalidação do §15.8 sob o
# lock do lead, no instante do post.
#
# Estados:
#   authorized -> a tentativa pode ser executada (claim/lease controlam a chamada ao up2-agents)
#   consumed   -> WhatsApp: a mensagem foi gravada (post aceito pelo gate), aguardando a confirmação
#                 real do provedor (source_id). E-mail: o relay SMTP aceitou a mensagem.
#   confirmed  -> a tentativa foi registrada no Engine (tentativa_recuperacao incrementada)
#   superseded -> o lead respondeu antes de a tentativa sair (§15.9)
#   cancelled  -> invalidada por fato mais novo (Assumir, não contatar)
#   failed     -> MAX_ATTEMPTS falhas técnicas -- terminal, o ciclo é interrompido e fica visível
#
# Uma conversa guarda só a tentativa corrente (uma chave); a trajetória fica nos lead_events.
module OperationalEngine
  class RecoveryActivation < OriginationActivation
    KEY = 'up_sales_recovery'.freeze
    STATUSES = %w[authorized consumed confirmed superseded cancelled failed].freeze
    MAX_ATTEMPTS = 3
    DISPATCH_LEASE = 10.minutes

    # Post gravado sem confirmação do provedor por mais que isto = a tentativa não saiu de verdade
    # (§23.3): conta como falha técnica e pode ser refeita, até MAX_ATTEMPTS. Técnico, por ENV.
    def self.confirmation_timeout
      ENV.fetch('UP_SALES_RECOVERY_CONFIRMATION_TIMEOUT_MINUTES', '120').to_i.minutes
    end

    # `elegivel_em` (proxima_recuperacao_em do passo) identifica o passo DENTRO do ciclo: retries da
    # mesma tentativa o compartilham; um ciclo novo (depois de resposta, Assumir/Devolver) tem outro
    # baseline e nunca herda uma ativação confirmada/esgotada do ciclo anterior.
    def self.build_attributes(lead, tentativa:, canal:, attempts: 0)
      {
        KEY => {
          'activation_id' => SecureRandom.uuid, 'lead_id' => lead.lead_id, 'tentativa' => tentativa, 'canal' => canal,
          'elegivel_em' => step_marker(lead), 'status' => 'authorized', 'authorized_at' => Time.current.iso8601(6), 'attempts' => attempts
        }
      }
    end

    def self.step_marker(lead)
      lead.proxima_recuperacao_em&.utc&.iso8601(6)
    end

    # Autoriza (ou retoma) a `tentativa` na conversa, sob o lock da conversa. Retorna
    # [ativação, estado]: :ok (pode executar), :consumida (e-mail aceito, falta registrar),
    # :aguardando_confirmacao (post gravado, esperando o provedor), :esgotada (falha terminal).
    def self.authorize!(conversation, lead, tentativa:, canal:)
      fresh = ::Conversation.find(conversation.id)
      result = nil
      fresh.with_lock do
        entry = fresh.additional_attributes&.dig(KEY)
        existing = entry.present? ? new(fresh, entry) : nil
        result = existing&.same_attempt?(lead, tentativa, canal) ? existing.resume_state(fresh, lead) : [write!(fresh, lead, tentativa, canal), :ok]
      end
      result
    end

    def self.write!(conversation, lead, tentativa, canal, attempts: 0)
      attributes = (conversation.additional_attributes || {}).merge(build_attributes(lead, tentativa: tentativa, canal: canal, attempts: attempts))
      conversation.update_columns(additional_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
      new(conversation, attributes[KEY])
    end

    def tentativa = @data['tentativa'].to_i
    def canal = @data['canal']
    def message_id = @data['message_id']
    def email_message_id = @data['email_message_id']

    def same_attempt?(lead, tentativa, canal)
      lead_id == lead.lead_id && self.tentativa == tentativa && self.canal == canal && @data['elegivel_em'] == self.class.step_marker(lead)
    end

    # Chamado sob o lock da conversa (authorize!).
    def resume_state(conversation, lead)
      case status
      when 'authorized' then [self, :ok]
      when 'failed' then [self, :esgotada]
      when 'consumed' then consumed_state(conversation, lead)
      when 'confirmed' then [self, :confirmada]
      else [self.class.write!(conversation, lead, tentativa, canal), :ok]
      end
    end

    private

    def consumed_state(conversation, lead)
      return [self, :consumida] if canal == 'email'
      return [nil, :aguardando_confirmacao] if status_at.present? && status_at > self.class.confirmation_timeout.ago
      return [self, :esgotada] if attempts >= MAX_ATTEMPTS

      # Post gravado e nunca confirmado: a mensagem não saiu (§23.3) -- nova autorização, mesma
      # tentativa, carregando o número de tentativas técnicas já gastas.
      [self.class.write!(conversation, lead, tentativa, canal, attempts: attempts), :ok]
    end
  end
end
