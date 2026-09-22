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
#    Campaigns::CampaignConversationBuilder já usa. A existência da conversa é o sinal de "já
#    reivindicado".
#
# Nunca segurar QUALQUER lock durante a chamada de rede pro up2-agents -- ela roda depois dos dois
# commits, sempre (mesmo raciocínio de SalesProjectionSync ficar fora do with_lock em
# TakeoverService: seria só "segurar mais tempo" sem ganhar atomicidade nenhuma, já que são bancos/
# conexões diferentes).
module OperationalEngine
  class Dispatcher
    def self.call(conta_id:)
      new(conta_id).call
    end

    def initialize(conta_id)
      @conta_id = conta_id
    end

    def call
      return unless agent_tenant&.dispatcher_ready?

      OperationalEngine::BacklogSelector.proximos(conta_id: @conta_id).find_each do |lead|
        originate(lead)
      end
    end

    private

    attr_reader :conta_id

    def agent_tenant
      @agent_tenant ||= UpSales::AgentTenant.find_by(account_id: @conta_id)
    end

    def originate(lead)
      return unless still_eligible?(lead)

      claim = claim_conversation(lead)
      return unless claim

      send_opening_message(lead, claim)
    end

    # Lock 1 (Supabase) -- só releitura, nada de escrita nem trabalho nativo aqui dentro.
    def still_eligible?(lead)
      lead.with_lock do
        lead.etapa_prospect_backlog? && lead.modo_atendimento_lavinia? && !lead.nao_contatar?
      end
    end

    # Lock 2 (Postgres nativo, conexão própria) -- protege contra o dispatcher rodando duas vezes
    # concorrentemente e criando duas conversas pro mesmo lead.
    def claim_conversation(lead)
      contact_inbox = ContactInboxWithContactBuilder.new(
        inbox: agent_tenant.whatsapp_inbox,
        contact_attributes: { phone_number: lead.telefone, name: lead.nome.presence || lead.empresa }
      ).perform

      result = nil

      ActiveRecord::Base.transaction do
        contact_inbox.lock!
        next if contact_inbox.reload.conversations.present?

        conversation = ::Conversation.create!(
          account_id: account.id,
          inbox_id: contact_inbox.inbox_id,
          contact_id: contact_inbox.contact_id,
          contact_inbox_id: contact_inbox.id
        )

        result = { contact_inbox: contact_inbox, conversation: conversation }
      end

      result
    end

    def send_opening_message(lead, claim)
      UpSales::Agents::OriginateConversationService.new(
        agent_tenant: agent_tenant,
        conversation: claim[:conversation],
        contact_inbox: claim[:contact_inbox]
      ).perform
    rescue UpSales::Agents::OriginateConversationService::SyncError => e
      Rails.logger.error("[OperationalEngine::Dispatcher] origination failed for lead #{lead.lead_id}: #{e.message}")
      OperationalEngine::LeadEvent.create!(
        lead: lead,
        event_type: 'primeiro_contato_falhou',
        source: 'system',
        metadata: { motivo: e.message, correlation_id: SecureRandom.uuid }
      )
    end

    def account
      agent_tenant.account
    end
  end
end
