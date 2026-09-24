# Fase 6, peça 2 (SSOT §10.5): o dispatcher em si. Por tick, por conta configurada: seleciona os
# próximos leads elegíveis do Backlog (BacklogSelector, já pronto -- FIFO + capacidade/janelas) e,
# pra cada um, origina o primeiro contato -- cria contato/conversa aqui, e a Lavínia (up2-agents)
# gera e ENVIA a mensagem de abertura (decisão registrada: reusa o caminho já testado de toda
# resposta reativa, não um contrato novo de "devolver texto pro Rails enviar").
#
# `entrada_operacao_em`/`primeiro_contato_em`/`etapa_prospect: contatado` continuam reservados pra
# ConfirmOutboundSendService reagindo ao source_id real (§10.6) -- este serviço NUNCA os grava.
# "Mensagem criada ≠ mensagem enviada" vale aqui também: originar a conversa não é ativação.
#
# Lock e concorrência -- DOIS locks pequenos, cada um na sua própria conexão, nunca um segurando
# trabalho da outra:
#
# 1. `lead.with_lock` (Supabase): só releitura + checagem de elegibilidade, nada mais. Honra o que
#    TakeoverService já deixou escrito ("qualquer leitura de modo_atendimento feita fora dessa
#    transação... tem que tomar o mesmo lock, ou a garantia não vale") -- hoje isso é defesa
#    antecipada, não um caso real observável (um lead em Backlog ainda não tem conversa nenhuma
#    pra um humano Assumir!), mas o lock sai barato e não força reabrir essa análise se uma fase
#    futura mudar isso.
# 2. `contact_inbox.lock!` (Postgres nativo, dentro de uma transaction própria): protege o risco
#    real -- o PRÓPRIO dispatcher rodando duas vezes concorrentemente (cron sobrepondo, retry
#    manual) e criando duas conversas pro mesmo lead. Mesma técnica que
#    Campaigns::CampaignConversationBuilder já usa. CP-02: a conversa é reaproveitada enquanto a
#    ativação estiver autorizada; quem impede duas chamadas simultâneas é o claim_attempt! (lease)
#    da OriginationActivation, e quem impede duas aberturas é o OutboundSendGate.
#
# Nunca segurar QUALQUER lock durante a chamada de rede pro up2-agents -- ela roda depois dos dois
# commits, sempre (mesmo raciocínio de SalesProjectionSync ficar fora do with_lock em
# TakeoverService: seria só "segurar mais tempo" sem ganhar atomicidade nenhuma, já que são bancos/
# conexões diferentes).
#
# CP-01 (P0-024-01): por isso mesmo `still_eligible?` NÃO é a autorização de envio -- entre ele e o
# post existem claim, geração no LLM e rede. A autorização final é do OutboundSendGate, que relê o
# lead sob o mesmo lock no momento em que a mensagem de abertura é gravada e confere a ativação
# (OriginationActivation) que este serviço grava na conversa reivindicada.
module OperationalEngine
  class Dispatcher
    def self.call(conta_id:)
      new(conta_id).call
    end

    def initialize(conta_id)
      @conta_id = conta_id
    end

    # CP-02: fila FIFO real (P1-024-02), capacidade contada só pelas originações que de fato
    # aconteceram neste tick -- leads com ativação em andamento/esgotada/já consumida são pulados
    # sem ocupar vaga (P1-024-01, sem head-of-line blocking) -- e pacing por inbox antes de cada
    # abordagem (P1-024-03).
    def call
      return unless agent_tenant&.dispatcher_ready?

      capacidade = OperationalEngine::BacklogCapacity.disponivel(conta_id: @conta_id)
      return if capacidade.zero?

      originadas = 0
      OperationalEngine::BacklogSelector.candidatos(conta_id: @conta_id).each do |lead|
        break if originadas >= capacidade
        break unless OperationalEngine::DispatchPacing.allows?(inbox_id: agent_tenant.whatsapp_inbox_id)

        originadas += 1 if originate(lead)
      end
    end

    private

    attr_reader :conta_id

    def agent_tenant
      @agent_tenant ||= UpSales::AgentTenant.find_by(account_id: @conta_id)
    end

    # true quando uma chamada de originação foi de fato feita (conta para capacidade e pacing).
    def originate(lead)
      return false unless still_eligible?(lead)

      claim = claim_or_resume(lead)
      return false unless claim&.dig(:activation)&.claim_attempt!

      send_opening_message(lead, claim)
      true
    end

    # Lock 1 (Supabase) -- só releitura, nada de escrita nem trabalho nativo aqui dentro. Mesmo
    # predicado do OutboundSendGate (CP-01): este filtro só evita trabalho inútil; a autorização que
    # vale é a do gate, no instante do post, porque entre aqui e lá ainda há claim + LLM + rede.
    def still_eligible?(lead)
      lead.with_lock do
        OperationalEngine::OutboundEligibility.origination_blockers(lead).empty?
      end
    end

    # Lock 2 (Postgres nativo, conexão própria) -- protege contra o dispatcher rodando duas vezes
    # concorrentemente e criando duas conversas pro mesmo lead.
    #
    # CP-02 (P1-024-01): conversa existente não é mais "já reivindicado para sempre" -- se ela carrega
    # uma ativação AINDA autorizada deste lead (tentativa anterior falhou antes da abertura sair), a
    # mesma ativação é retomada na mesma conversa. Abertura já gravada, ativação invalidada/esgotada
    # ou conversa sem ativação (histórica, humana) nunca são reoriginadas.
    def claim_or_resume(lead)
      contact_inbox = ContactInboxWithContactBuilder.new(
        inbox: agent_tenant.whatsapp_inbox,
        contact_attributes: { phone_number: lead.telefone, name: lead.nome.presence || lead.empresa }
      ).perform

      result = nil
      ActiveRecord::Base.transaction do
        contact_inbox.lock!
        conversation = contact_inbox.reload.conversations.order(:id).last || create_conversation(contact_inbox, lead)
        activation = OperationalEngine::OriginationActivation.for(conversation)
        next unless activation&.authorized? && activation.lead_id == lead.lead_id

        result = { contact_inbox: contact_inbox, conversation: conversation, activation: activation }
      end
      result
    end

    # A autorização desta ativação nasce junto com a conversa (mesma transação): o OutboundSendGate
    # só aceita a abertura se ela ainda estiver "authorized" e o lead ainda elegível no instante do
    # post (CP-01, P0-024-01).
    def create_conversation(contact_inbox, lead)
      ::Conversation.create!(
        account_id: account.id,
        inbox_id: contact_inbox.inbox_id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead)
      )
    end

    def send_opening_message(lead, claim)
      UpSales::Agents::OriginateConversationService.new(
        agent_tenant: agent_tenant,
        conversation: claim[:activation].conversation,
        contact_inbox: claim[:contact_inbox]
      ).perform
    rescue UpSales::Agents::OriginateConversationService::SyncError => e
      record_failure(lead, claim[:activation], e.message)
    end

    # §28.2: falha mantém o lead em Backlog, sem timestamps de sucesso. CP-02 (P1-024-01/§23.3):
    # retries limitados e observáveis -- cada tentativa falha vira evento com o número da tentativa;
    # ao esgotar MAX_ATTEMPTS a ativação vira failed (terminal) e o evento sai marcado para
    # intervenção humana.
    def record_failure(lead, activation, motivo)
      terminal = activation.attempts >= OperationalEngine::OriginationActivation::MAX_ATTEMPTS
      activation.transition!('failed', motivo: motivo) if terminal
      Rails.logger.error(
        "[OperationalEngine::Dispatcher] origination failed for lead #{lead.lead_id} " \
        "(tentativa #{activation.attempts}#{', terminal' if terminal}): #{motivo}"
      )
      OperationalEngine::LeadEvent.create!(
        lead: lead, event_type: 'primeiro_contato_falhou', source: 'system',
        metadata: { motivo: motivo, tentativa: activation.attempts, terminal: terminal,
                    activation_id: activation.activation_id, correlation_id: SecureRandom.uuid }
      )
    end

    def account
      agent_tenant.account
    end
  end
end
