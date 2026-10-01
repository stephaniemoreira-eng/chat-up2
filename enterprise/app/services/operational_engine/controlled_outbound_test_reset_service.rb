# Homologação controlada: devolve um lead de teste ao ponto inicial de uma abordagem outbound.
#
# A proteção de produção contra uma segunda abertura (OutboundSendGate#other_activation_consumed?)
# deve continuar intacta. Em homologação, porém, um reteste não pode herdar a ativação `consumed`
# de uma conversa histórica do mesmo contato. Este serviço remove APENAS as chaves técnicas de
# coordenação de todas as conversas daquele contato e registra o reset no histórico append-only do
# Engine. Mensagens e eventos anteriores não são apagados.
#
# A variável é propositalmente opt-in: ela só deve existir no serviço Rails de homologação. Em
# produção, a ausência da variável torna qualquer chamada um erro explícito.
module OperationalEngine
  class ControlledOutboundTestResetService
    ENABLED_ENV = 'UP_SALES_TEST_RESET_ENABLED'.freeze
    ACTIVATION_KEYS = [OriginationActivation::KEY, RecoveryActivation::KEY].freeze

    BASELINE_ATTRIBUTES = {
      modo_entrada: 'outbound',
      etapa_prospect: 'backlog',
      lead_status: 'ativo',
      qualificacao_status: 'em_qualificacao',
      recuperacao_status: 'inativa',
      tentativa_recuperacao: 0,
      proxima_recuperacao_em: nil,
      aguardando_resposta: false,
      agendamento_status: 'nao_iniciado',
      orcamento_status: 'nao_solicitado',
      resultado_comercial: 'em_aberto',
      modo_atendimento: 'lavinia',
      frente_operacional: 'prospeccao',
      etapa_comercial: nil,
      nao_contatar: false,
      propensao_fechamento: 'nao_classificado',
      motivo_handoff: nil,
      motivo_encerramento: nil,
      primeiro_contato_em: nil,
      primeira_resposta_em: nil,
      ultima_interacao_em: nil,
      qualificado_em: nil,
      agendado_em: nil,
      upsales_conversation_atual_id: nil
    }.freeze

    Result = Data.define(:conversation_ids, :correlation_id)

    def self.call(...)
      new(...).call
    end

    def initialize(lead:, reason:)
      @lead = lead
      @reason = reason.to_s.strip
    end

    def call
      raise ArgumentError, "#{ENABLED_ENV} precisa ser true para resetar um lead de teste" unless enabled?
      raise ArgumentError, 'motivo do reset é obrigatório' if @reason.blank?

      @lead.with_lock do
        conversation_ids = clear_technical_activations
        now = Time.current
        @lead.update!(BASELINE_ATTRIBUTES.merge(etapa_entrou_em: now))

        correlation_id = SecureRandom.uuid
        LeadEvent.create!(
          lead: @lead,
          event_type: 'massa_teste_resetada',
          source: 'system',
          metadata: {
            motivo: @reason,
            chaves_tecnicas_removidas: ACTIVATION_KEYS,
            conversas_limpas: conversation_ids,
            correlation_id: correlation_id
          }
        )

        Result.new(conversation_ids, correlation_id)
      end
    end

    private

    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(ENABLED_ENV, false))
    end

    def clear_technical_activations
      conversations_for_contact.filter_map do |conversation|
        conversation.with_lock do
          attributes = (conversation.additional_attributes || {}).dup
          changed = ACTIVATION_KEYS.any? { |key| attributes.delete(key) }
          next unless changed

          conversation.update_columns(additional_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
          conversation.id
        end
      end
    end

    def conversations_for_contact
      return ::Conversation.none if contact_ids.empty?

      ::Conversation.where(account_id: @lead.conta_id, contact_id: contact_ids)
    end

    def contact_ids
      @contact_ids ||= begin
        ids = [@lead.upsales_contact_id].compact
        ids.presence || ::Contact.where(account_id: @lead.conta_id, phone_number: @lead.telefone).pluck(:id)
      end
    end
  end
end
