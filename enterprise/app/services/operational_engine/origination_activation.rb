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
module OperationalEngine
  class OriginationActivation
    KEY = 'up_sales_origination'.freeze
    STATUSES = %w[authorized consumed superseded cancelled].freeze

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

    # update_columns de propósito: é estado técnico de coordenação, não uma edição da conversa --
    # não deve disparar CONVERSATION_UPDATED, webhooks nem reatribuição. O lock da própria conversa
    # evita que dois escritores concorrentes se atropelem no merge do jsonb.
    def transition!(new_status, **extra)
      raise ArgumentError, "status inválido: #{new_status}" unless STATUSES.include?(new_status)

      conversation.with_lock do
        current = (conversation.additional_attributes || {}).dup
        entry = (current[KEY] || @data).merge('status' => new_status, 'status_at' => Time.current.iso8601(6))
        entry.merge!(extra.transform_keys(&:to_s))
        current[KEY] = entry
        conversation.update_columns(additional_attributes: current)
        @data = entry
      end
      self
    end
  end
end
