# Fluxo inbound do SSOT §11.1/§11.2 e §5.4, testes 28.6 (inbound novo) e 28.8 (lead existente por
# nova origem). Chamado pelo listener pra toda MESSAGE_CREATED cujo `message.incoming?` -- ou
# seja, mensagem do contato pro Chatwoot, nunca uma resposta nossa.
#
# Escopo deliberadamente estreito: resolve/cria o lead e registra os fatos de entrada. NÃO monta
# o Snapshot da Lavínia (Fase 4/§12.3) nem decide qualificação -- isso é regra de negócio de fases
# seguintes. Um lead novo nasce direto em `em_conversa` (28.6): não há Backlog/Contatado no
# caminho inbound, esses status só existem pro lado outbound.
#
# CP-16A (P2-VAL-15; decisão da Stéphanie em 24/09/2026, lacuna do SSOT): um lead que ainda está em
# Backlog (importado, nunca abordado) e manda a primeira mensagem ANTES da abertura do Dispatcher
# sair é tratado como INBOUND -- pergunta "tratar como inbound?", resposta dela: "SIM". Aplica o
# §11.2 sobre o lead existente (ver #register_backlog_inbound); origem_lead continua a importada.
module OperationalEngine
  class InboundProcessor
    BACKLOG_INBOUND_MOTIVO = 'lead_iniciou_antes_da_abertura'.freeze

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
    #
    # CP-13 (P1-VAL-12, §15.9 "timers pendentes cancelados"): o mesmo vale para uma tentativa de
    # recovery autorizada e ainda não gravada nesta conversa.
    def supersede_pending_opening
      [OperationalEngine::OriginationActivation, OperationalEngine::RecoveryActivation].each do |klass|
        activation = klass.for(@conversation)
        activation.transition!('superseded', message_id: @message.id) if activation&.authorized?
      end
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
    # banco); só atualiza onde o lead está sendo operado agora e registra a ocorrência. Cada
    # mensagem inbound é um fato operacional e deve manter a trilha append-only em lead_events;
    # o conteúdo completo continua exclusivamente no UpSales (§7.2).
    #
    # CP-08 (P1-VAL-01; SSOT §11.3, teste 28.3): a primeira resposta real de um lead Contatado o
    # leva para Em conversa sob o lock do lead (mesmo lock do OutboundSendGate/TakeoverService) --
    # a releitura dentro do lock torna o reprocessamento do mesmo webhook um no-op (28.9).
    def handle_existing(lead)
      lead.with_lock do
        mudou_de_inbox = lead.inbox_atual_id != @inbox.id
        inbound_from_backlog = lead.etapa_prospect_backlog? && lead.lead_status_ativo?
        lead.update!(
          ultima_interacao_em: @message.created_at,
          upsales_conversation_atual_id: @conversation.id,
          **(mudou_de_inbox ? { inbox_atual_id: @inbox.id } : {})
        )
        # Antes do nova_entrada genérico de propósito: mesma chave de idempotência (tipo + message_id),
        # então o evento que fica é o da entrada na operação, com o modo e o motivo.
        register_backlog_inbound(lead) if inbound_from_backlog
        write_event(lead, 'nova_entrada', inbox_atual_id: @inbox.id) if mudou_de_inbox
        if lead.etapa_prospect_contatado?
          register_outbound_reply(lead)
        elsif !inbound_from_backlog
          write_event(lead, 'lead_respondeu', message_id: @message.id)
        end
        register_recovery_reply(lead)
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'inbound')
      end
      lead
    end

    # CP-16A (P2-VAL-15; Stéphanie, 24/09/2026: lead em Backlog que fala antes da abertura = inbound
    # -- "SIM"). §11.2 aplicado ao lead existente, sob o mesmo lock do handle_existing:
    # - modo_entrada = inbound (não é write-once no §6.3; o lead nunca foi abordado, então nunca foi
    #   de fato outbound);
    # - entrada_operacao_em / inbox_entrada_id = esta mensagem/inbox SÓ se nulos (write-once, §6.3 --
    #   o trigger do Engine recusaria sobrescrever);
    # - etapa_prospect backlog -> em_conversa, etapa_entrou_em = horário da mensagem;
    # - nova_entrada + etapa_alterada {motivo: lead_iniciou_antes_da_abertura}, idempotentes pelo
    #   message_id (EventWriter). lead_criado NÃO: o lead já existia (importado).
    # origem_lead fica a da importação (write-once, §5.4). Fora de backlog o Dispatcher não o seleciona
    # mais (BacklogSelector/OutboundEligibility exigem backlog) e a ativação pendente já foi superseded
    # em #supersede_pending_opening; o Dashboard (CP-11) o conta como inbound pela coorte de
    # entrada_operacao_em + modo_entrada.
    # Só lead ATIVO: um lead de Backlog já encerrado (ex.: cliente atual raspado, P2-VAL-06, ou não
    # contatar) nunca teria abertura -- continua fora da operação Prospect; o gate só o deixa receber
    # resposta ao que ele mandou (§19.1/§19.2).
    def register_backlog_inbound(lead)
      lead.update!(
        modo_entrada: 'inbound',
        etapa_prospect: 'em_conversa',
        etapa_entrou_em: @message.created_at,
        entrada_operacao_em: lead.entrada_operacao_em || @message.created_at,
        inbox_entrada_id: lead.inbox_entrada_id || @inbox.id
      )
      write_event(lead, 'nova_entrada', inbox_atual_id: @inbox.id, modo_entrada: 'inbound', motivo: BACKLOG_INBOUND_MOTIVO)
      write_event(lead, 'etapa_alterada', de: 'backlog', para: 'em_conversa', motivo: BACKLOG_INBOUND_MOTIVO)
    end

    # §11.3: contatado -> em_conversa, primeira_resposta_em se vazio, eventos lead_respondeu +
    # etapa_alterada. O cancelamento do recovery (§11.3 "cancelar recovery") é o de QUALQUER
    # resposta -- register_recovery_reply, logo em seguida, no mesmo lock.
    def register_outbound_reply(lead)
      lead.update!(
        etapa_prospect: 'em_conversa',
        etapa_entrou_em: @message.created_at,
        primeira_resposta_em: lead.primeira_resposta_em || @message.created_at
      )
      write_event(lead, 'lead_respondeu', message_id: @message.id)
      write_event(lead, 'etapa_alterada', de: 'contatado', para: 'em_conversa', motivo: 'lead_respondeu')
    end

    # CP-13 (P1-VAL-12; SSOT §15.9, 28.4 final): qualquer resposta real, em qualquer etapa -- recovery
    # inativa, tentativa 0, próxima null (o timer armado some junto). recuperacao_respondida só quando
    # o ciclo já estava ativo (armado e não vencido não é "precisou de recovery", §22.7). A continuação
    # pelo ultimo_ponto é da Lavínia no turno reativo (ultimo_ponto não é apagado). Se parar de novo,
    # o próximo envio confirmado arma um ciclo novo na tentativa 1.
    def register_recovery_reply(lead)
      before = OperationalEngine::RecoveryCycle.reset_on_reply!(lead)
      return unless before&.dig(:ativa)

      write_event(lead, 'recuperacao_respondida', message_id: @message.id, tentativa: before[:tentativa],
                                                  ultimo_ponto: before[:ultimo_ponto], inbox_id: @inbox.id)
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
