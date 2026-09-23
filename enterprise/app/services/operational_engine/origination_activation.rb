# CP-01 (P0-024-01, P0-022-02): a autorização de UMA primeira abordagem, gravada pelo Dispatcher
# na conversa que ele reivindica e consumida pelo OutboundSendGate no post público. É o que liga
# "o Dispatcher decidiu abordar este lead" a "esta mensagem é aquela abordagem" -- sem isso o gate
# não sabe distinguir a abertura de uma resposta reativa qualquer.
#
# Mora em `conversations.additional_attributes` (Postgres nativo), não no Supabase: §23.1 permite
# que o armazenamento técnico de idempotência/coordenação fique no backend do UpSales, sem virar
# fato de negócio. `activation_id` é a identidade estável da ativação -- o CP-02 (retry/claim
# recuperável) e o CP-03 (identidade do turno) devem reutilizá-la, não criar outra.
#
# Estados:
#   authorized -> a abertura ainda pode sair (se o lead continuar elegível no instante do post)
#   consumed   -> a abertura foi gravada; mensagens seguintes seguem as regras normais do gate
#   superseded -> o contato falou antes da abertura sair (resposta nova, §23.2)
#   cancelled  -> invalidada por fato mais novo no Engine (ex.: ativar_nao_contatar)
#   failed     -> CP-02 (P1-024-01): a originação falhou MAX_ATTEMPTS vezes -- erro terminal visível
#                 (evento primeiro_contato_falhou com terminal=true), fica para intervenção humana
#
# CP-02 (P1-024-01): "conversa existe" deixou de significar "ativação concluída". Enquanto a
# ativação está authorized, o Dispatcher pode retomá-la na MESMA conversa (sem criar outra) depois
# de uma falha transitória -- mas só uma chamada por vez (lease de DISPATCH_LEASE) e no máximo
# MAX_ATTEMPTS vezes. Uma abertura já gravada (consumed) nunca é reoriginada.
module OperationalEngine
  class OriginationActivation
    KEY = 'up_sales_origination'.freeze
    STATUSES = %w[authorized consumed superseded cancelled failed].freeze
    MAX_ATTEMPTS = 3
    DISPATCH_LEASE = 10.minutes

    def self.build_attributes(lead)
      {
        KEY => {
          'activation_id' => SecureRandom.uuid,
          'lead_id' => lead.lead_id,
          'status' => 'authorized',
          'authorized_at' => Time.current.iso8601(6)
        }
      }
    end

    def self.for(conversation)
      data = conversation.additional_attributes&.dig(KEY)
      data.present? ? new(conversation, data) : nil
    end

    # Todas as ativações ainda "authorized" do contato do lead nesta conta -- usado pelo opt-out
    # pra invalidar outbound pendente de forma verificável (P0-018-01).
    def self.pending_for_contact(account_id:, contact_id:)
      ::Conversation.where(account_id: account_id, contact_id: contact_id)
                    .where("additional_attributes -> '#{KEY}' ->> 'status' = ?", 'authorized')
                    .filter_map { |conversation| self.for(conversation) }
    end

    attr_reader :conversation

    def initialize(conversation, data)
      @conversation = conversation
      @data = data
    end

    def activation_id = @data['activation_id']
    def lead_id = @data['lead_id']
    def status = @data['status']
    def authorized_at = Time.zone.parse(@data['authorized_at'].to_s)

    def authorized? = status == 'authorized'
    def status_at = @data['status_at'].presence && Time.zone.parse(@data['status_at'])
    def attempts = @data['attempts'].to_i

    # Pode chamar o up2-agents agora? Autorizada, abaixo do teto de tentativas e sem outra chamada
    # em andamento (lease).
    def dispatchable?(now = Time.current)
      return false unless authorized? && attempts < MAX_ATTEMPTS

      last = @data['last_attempt_at'].presence && Time.zone.parse(@data['last_attempt_at'])
      last.nil? || last <= now - DISPATCH_LEASE
    end

    # Reivindica a próxima tentativa sob o lock da conversa -- dois dispatchers concorrentes não
    # chamam o up2-agents juntos para a mesma ativação.
    def claim_attempt!(now = Time.current)
      claimed = false
      fresh = ::Conversation.find(conversation.id)
      fresh.with_lock do
        entry = fresh.additional_attributes&.dig(KEY)
        next unless entry && self.class.new(fresh, entry).dispatchable?(now)

        entry = entry.merge('attempts' => entry['attempts'].to_i + 1, 'last_attempt_at' => now.iso8601(6))
        fresh.update_columns(additional_attributes: fresh.additional_attributes.merge(KEY => entry)) # rubocop:disable Rails/SkipsModelValidations
        @data = entry
        claimed = true
      end
      @conversation = fresh
      claimed
    end

    # update_columns de propósito: é estado técnico de coordenação, não uma edição da conversa --
    # não deve disparar CONVERSATION_UPDATED, webhooks nem reatribuição. O lock da própria conversa
    # evita que dois escritores concorrentes se atropelem no merge do jsonb. Trava uma instância
    # recém-lida: o objeto recebido pode ter atributos sujos (callbacks de criação, por exemplo), e
    # o Rails recusa `with_lock` nesse caso.
    def transition!(new_status, **extra)
      raise ArgumentError, "status inválido: #{new_status}" unless STATUSES.include?(new_status)

      fresh = ::Conversation.find(conversation.id)
      fresh.with_lock do
        current = (fresh.additional_attributes || {}).dup
        entry = (current[KEY] || @data).merge('status' => new_status, 'status_at' => Time.current.iso8601(6))
        entry.merge!(extra.transform_keys(&:to_s))
        current[KEY] = entry
        fresh.update_columns(additional_attributes: current) # rubocop:disable Rails/SkipsModelValidations
        @data = entry
      end
      @conversation = fresh
      self
    end
  end
end
