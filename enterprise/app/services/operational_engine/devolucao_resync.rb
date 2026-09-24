# CP-16B (P2-VAL-20; SSOT §18.3 "Antes de reativar: sincronizar ... `ultimo_ponto`", §12.3, §23.1,
# §28.22). Decisão da Stéphanie em 24/09/2026, fechando a lacuna que o CP-06 registrou em
# OperationalEngine::DevolucaoSync ("quem redige o novo ponto de continuidade de uma conversa conduzida
# por humano"):
#
#   "A LAVÍNIA ANALISA A CONVERSA NOVAMENTE E VÊ AONDE O CONTEXTO TERMINA E INTERPRETA QUAL O
#    ultimo_ponto PARA CONTINUAÇÃO DA CONVERSA, SE NECESSÁRIO."
#
# Depois do commit da devolução (TakeoverService#devolver!, fora do lock), o Engine pede ao up2-agents
# um TURNO SILENCIOSO de ressincronização: mesmo agente, mesmo Prompt V1.0 (nada é acrescentado ao
# prompt), Snapshot com o estado atual e as mensagens recentes da conversa -- inclusive as do humano
# (TurnMessages, autor `humano`). Desse turno só a saída estruturada é aproveitada, pelo caminho de
# commit de sempre (POST operational_engine/turno -> ApplyStructuredOutputService, modo
# `ressincronizacao`, turn_id `devolucao:<id>`):
#
# - "SE NECESSÁRIO": `ultimo_ponto` vazio/igual não sobrescreve nada (regra do commit, 28.5);
# - só fatos de continuidade entram (ultimo_ponto, resumo_oportunidade, dados_extraidos da whitelist);
#   decisao_qualificacao, aguardando_resposta e acao_sugerida são descartados pelo Engine -- é só
#   ressincronização, nenhuma ação operacional é disparada (ApplyStructuredOutputService);
# - nada vai ao lead: o up2-agents não cria cliente Chatwoot nesse turno, e um post carimbado
#   RESSINCRONIZACAO seria recusado pelo gate de qualquer forma (AutomationSendRules);
# - falha não desfaz a devolução (já confirmada): o job tenta de novo um número limitado de vezes
#   (UP_SALES_DEVOLUCAO_RESYNC_ATTEMPTS) e, esgotado, registra o evento e mantém o `ultimo_ponto`
#   anterior;
# - idempotente: a identidade da devolução é a correlation_id da transição (eventos
#   intervencao_humana_encerrada/modo_atendimento_alterado) -- o commit repetido do mesmo turno é
#   replay no ledger. Uma devolução que já não é a vigente (humano reassumiu, ou houve outra devolução
#   depois) não ressincroniza.
module OperationalEngine
  class DevolucaoResync
    def self.turn_id(devolucao_id)
      "devolucao:#{devolucao_id}"
    end

    def self.schedule(lead, devolucao_id)
      return if lead.upsales_conversation_atual_id.blank?

      OperationalEngine::DevolucaoResyncJob.perform_later(lead.lead_id, devolucao_id, lead.modo_atendimento_entrou_em&.iso8601(6))
    rescue StandardError => e
      # Nunca derruba o Devolver já gravado.
      Rails.logger.error("[OperationalEngine::DevolucaoResync] lead=#{lead.lead_id} falha ao agendar: #{e.class}: #{e.message}")
    end

    # A devolução `devolucao_id` ainda é a vigente deste lead: o lead está com a Lavínia, a intervenção
    # encerrada com essa identidade existe e -- quando informado -- o instante em que o modo voltou para
    # `lavinia` é o dessa devolução (um Assumir/Devolver posterior troca modo_atendimento_entrou_em).
    # Não depende da ordem dos eventos (event_at vem do banco e pode empatar numa mesma transação).
    def self.current?(lead, devolucao_id, devolvido_em = nil)
      return false if devolucao_id.blank? || !lead.modo_atendimento_lavinia?
      return false if devolvido_em.present? && !same_instant?(lead.modo_atendimento_entrou_em, devolvido_em)

      lead.events.where(event_type: 'intervencao_humana_encerrada').exists?(["metadata ->> 'correlation_id' = ?", devolucao_id.to_s])
    end

    def self.same_instant?(time, iso)
      parsed = Time.zone.parse(iso.to_s)
      time.present? && parsed.present? && (time - parsed).abs < 0.001
    rescue ArgumentError
      false
    end

    def self.call(lead_id:, devolucao_id:, devolvido_em: nil)
      new(lead_id, devolucao_id, devolvido_em).call
    end

    def initialize(lead_id, devolucao_id, devolvido_em)
      @lead_id = lead_id
      @devolucao_id = devolucao_id
      @devolvido_em = devolvido_em
    end

    # => :skipped (nada a fazer) | resposta do up2-agents. Levanta SyncError para o job tentar de novo.
    def call
      lead = OperationalEngine::Lead.find_by(lead_id: @lead_id)
      return :skipped unless lead && self.class.current?(lead, @devolucao_id, @devolvido_em)

      conversation = ::Conversation.find_by(id: lead.upsales_conversation_atual_id, account_id: lead.conta_id)
      agent_tenant = UpSales::AgentTenant.find_by(account_id: lead.conta_id)
      return :skipped if conversation.nil? || agent_tenant.nil?

      UpSales::Agents::ResyncConversationService.new(agent_tenant: agent_tenant, conversation: conversation, devolucao_id: @devolucao_id).perform
    end

    def self.record_failure(lead_id, devolucao_id, error)
      lead = OperationalEngine::Lead.find_by(lead_id: lead_id)
      return if lead.nil?

      OperationalEngine::LeadEvent.create!(
        lead: lead, event_type: 'ressincronizacao_devolucao_falhou', source: 'system',
        metadata: { devolucao_id: devolucao_id, erro: error.message.to_s.first(500), ultimo_ponto_mantido: lead.ultimo_ponto,
                    correlation_id: devolucao_id }
      )
    end
  end
end
