# Fluxo inbound do SSOT §11.1/§11.2 e §5.4, testes 28.6 (inbound novo) e 28.8 (lead existente por
# nova origem). Chamado pelo listener pra toda MESSAGE_CREATED cujo `message.incoming?` -- ou
# seja, mensagem do contato pro Chatwoot, nunca uma resposta nossa.
#
# Escopo deliberadamente estreito: resolve/cria o lead e registra os fatos de entrada. NÃO monta
# o Snapshot da Lavínia (Fase 4/§12.3) nem decide qualificação -- isso é regra de negócio de fases
# seguintes. Um lead novo nasce direto em `em_conversa` (28.6): não há Backlog/Contatado no
# caminho inbound, esses status só existem pro lado outbound (Fase 6, ainda não construída).
module OperationalEngine
  class InboundProcessor
    def self.call(message:)
      new(message).call
    end

    def initialize(message)
      @message = message
      @conversation = message.conversation
      @contact = @conversation.contact
      @inbox = @conversation.inbox
      @account = message.account
    end

    def call
      return unless @contact&.phone_number.present?

      # find_by_telefone (não Lead.find_by direto) de propósito: normaliza por dentro, e um
      # find_by sem normalizar podia não achar um lead que já existe e cair em handle_new por
      # engano -- os eventos lead_criado/nova_entrada abaixo seriam escritos indevidamente pra um
      # lead que não é novo (LeadRepository.find_or_create_by_telefone evitaria o registro
      # duplicado em si, mas não os eventos espúrios).
      telefone = @contact.phone_number
      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: @account.id, telefone: telefone)

      lead = lead ? handle_existing(lead) : handle_new(telefone)

      OperationalEngine::SalesProjectionSync.call(lead)
      OperationalEngine::ComercialProjectionSync.call(lead)
      lead
    end

    private

    def handle_new(telefone)
      lead = OperationalEngine::LeadRepository.find_or_create_by_telefone(
        conta_id: @account.id,
        telefone: telefone,
        attributes: {
          nome: @contact.name,
          origem_lead: 'inbound_direto',
          modo_entrada: 'inbound',
          tipo_entrada: 'novo',
          relacao_atual: 'desconhecido',
          inbox_entrada_id: @inbox.id,
          inbox_atual_id: @inbox.id,
          entrada_operacao_em: @message.created_at,
          etapa_prospect: 'em_conversa',
          etapa_entrou_em: @message.created_at,
          ultima_interacao_em: @message.created_at,
          upsales_contact_id: @contact.id,
          upsales_conversation_atual_id: @conversation.id
        }
      )

      %w[lead_criado nova_entrada].each { |type| write_event(lead, type) }
      write_event(lead, 'etapa_alterada', de: nil, para: 'em_conversa')
      lead
    end

    # §5.4: nova origem não duplica o lead nem sobrescreve origem_lead (write-once, garantido no
    # banco); só atualiza onde o lead está sendo operado agora e registra a ocorrência. Mesma
    # inbox de sempre -> só toca ultima_interacao_em, sem evento (não é um fato de negócio novo).
    def handle_existing(lead)
      mudou_de_inbox = lead.inbox_atual_id != @inbox.id

      lead.update!(
        ultima_interacao_em: @message.created_at,
        upsales_conversation_atual_id: @conversation.id,
        **(mudou_de_inbox ? { inbox_atual_id: @inbox.id } : {})
      )

      write_event(lead, 'nova_entrada', inbox_atual_id: @inbox.id) if mudou_de_inbox
      lead
    end

    # external_id é só o message_id: o event_type já entra na chave composta do
    # IdempotencyGuard (conta_id + event_type + external_source + external_id), então
    # lead_criado/nova_entrada/etapa_alterada pra essa mensagem já deduplicam independentemente
    # sem precisar de um external_id artificialmente diferente por tipo.
    def write_event(lead, event_type, **metadata)
      OperationalEngine::EventWriter.call(
        lead: lead,
        event_type: event_type,
        source: 'system',
        external_source: 'chatwoot',
        external_id: @message.id.to_s,
        metadata: metadata
      )
    end
  end
end
