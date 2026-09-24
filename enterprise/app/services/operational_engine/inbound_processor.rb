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
      supersede_pending_opening
      return unless @contact&.phone_number.present?

      # find_by_telefone (não Lead.find_by direto) de propósito: normaliza por dentro, e um
      # find_by sem normalizar podia não achar um lead que já existe e cair em handle_new por
      # engano -- os eventos lead_criado/nova_entrada abaixo seriam escritos indevidamente pra um
      # lead que não é novo (LeadRepository.find_or_create_by_telefone evitaria o registro
      # duplicado em si, mas não os eventos espúrios).
      telefone = @contact.phone_number
      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: @account.id, telefone: telefone)

      lead = lead ? handle_existing(lead) : handle_new(telefone)

      # CP-08 (resíduo do CP-05, P1-025-04): projeção pelo mecanismo durável -- falha no CRM não
      # derruba o processamento do inbound (o fato já está no Engine) e é reconciliada depois.
      OperationalEngine::ProjectionReconciler.flush(lead)
      lead
    end

    private

    # CP-01 (§23.2, "resposta nova"): o contato falou antes da abertura do Dispatcher sair -- a
    # ativação deixa de valer. A partir daqui a conversa é reativa; a abertura já gerada não tem
    # mais autorização de primeira abordagem no OutboundSendGate.
    def supersede_pending_opening
      activation = OperationalEngine::OriginationActivation.for(@conversation)
      activation.transition!('superseded', message_id: @message.id) if activation&.authorized?
    end

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
      lead.with_lock { OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'inbound') }
      lead
    end

    # §5.4: nova origem não duplica o lead nem sobrescreve origem_lead (write-once, garantido no
    # banco); só atualiza onde o lead está sendo operado agora e registra a ocorrência. Mesma
    # inbox de sempre -> só toca ultima_interacao_em, sem evento (não é um fato de negócio novo).
    #
    # CP-08 (P1-VAL-01; SSOT §11.3, teste 28.3): a primeira resposta real de um lead Contatado o
    # leva para Em conversa sob o lock do lead (mesmo lock do OutboundSendGate/TakeoverService) --
    # a releitura dentro do lock torna o reprocessamento do mesmo webhook um no-op (28.9).
    def handle_existing(lead)
      lead.with_lock do
        mudou_de_inbox = lead.inbox_atual_id != @inbox.id
        lead.update!(
          ultima_interacao_em: @message.created_at,
          upsales_conversation_atual_id: @conversation.id,
          **(mudou_de_inbox ? { inbox_atual_id: @inbox.id } : {})
        )
        write_event(lead, 'nova_entrada', inbox_atual_id: @inbox.id) if mudou_de_inbox
        register_outbound_reply(lead) if lead.etapa_prospect_contatado?
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'inbound')
      end
      lead
    end

    # §11.3: contatado -> em_conversa, primeira_resposta_em se vazio, cancelar recovery,
    # eventos lead_respondeu + etapa_alterada (e recuperacao_respondida se havia recovery ativa).
    def register_outbound_reply(lead)
      recovery_ativa = lead.recuperacao_status_ativa?
      lead.update!(
        etapa_prospect: 'em_conversa',
        etapa_entrou_em: @message.created_at,
        primeira_resposta_em: lead.primeira_resposta_em || @message.created_at,
        recuperacao_status: 'inativa',
        proxima_recuperacao_em: nil
      )
      write_event(lead, 'lead_respondeu', message_id: @message.id)
      write_event(lead, 'etapa_alterada', de: 'contatado', para: 'em_conversa', motivo: 'lead_respondeu')
      write_event(lead, 'recuperacao_respondida', message_id: @message.id) if recovery_ativa
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
