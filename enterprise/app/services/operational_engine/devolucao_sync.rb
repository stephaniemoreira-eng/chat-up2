# CP-06 (P1-026-01; SSOT §18.3 "Antes de reativar: sincronizar mensagens relevantes, campos
# alterados, etapa/estado, ações comerciais, última mensagem do lead, última mensagem humana e
# `ultimo_ponto`", §26.3, §28.22, §34 "devolver exige ressincronização").
#
# Pré-condição do Devolver: roda DENTRO do `lead.with_lock` do TakeoverService, ANTES de
# modo_atendimento virar `lavinia`. Se levantar SyncError, a transação inteira volta -- o lead
# continua humano e com o responsável (critério de aceite do P1-026-01).
#
# O que "sincronizar" significa aqui, dimensão por dimensão:
# - mensagens relevantes / última do lead / última humana: lidas da conversa atual do lead
#   (fonte = Chatwoot, onde o humano conversou) e devolvidas como fatos -- `ultima_interacao_em`
#   é recalculado a partir delas (se o InboundProcessor perdeu alguma, a fotografia é corrigida
#   aqui) e o resumo vai no evento `intervencao_humana_encerrada`. O conteúdo das mensagens NÃO
#   é copiado para o Engine: o Snapshot do próximo turno já as entrega (TurnMessages, com
#   autor "humano"), sem uma segunda fonte de contexto (rastreabilidade do dossiê: P1-017-01/
#   P1-021-03).
# - campos alterados, etapa/estado e ações comerciais: desde o CP-05 toda ação humana sobre um
#   lead do Engine passa pelo próprio Engine (Assumir, Comercial, callback, NO-SHOW...), então o
#   estado já está no Engine; a sincronização valida e registra a fotografia com que a Lavínia volta.
# - `ultimo_ponto`: mantido como está AQUI (dentro do lock, antes de reativar). A lacuna do CP-06
#   ("quem redige o novo ponto de continuidade de uma conversa conduzida por humano") foi DECIDIDA pela
#   Stéphanie em 24/09/2026 (CP-16B, P2-VAL-20): a Lavínia relê a conversa num turno silencioso depois
#   do commit da devolução e o Engine grava o novo ponto, se houver -- ver OperationalEngine::DevolucaoResync.
#
# Falha fechado: conversa informada mas inexistente, de outra conta ou de outro contato, ou banco
# nativo indisponível -> SyncError (o operador vê o erro e repete; nada foi reativado).
module OperationalEngine
  class DevolucaoSync
    class SyncError < StandardError; end

    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    # => { lead_attributes: {...para gravar no lead...}, sincronizacao: {...para o evento...} }
    def call
      conversation = resolve_conversation
      return { lead_attributes: {}, sincronizacao: estado.merge(conversation_id: nil) } if conversation.nil?

      facts = message_facts(conversation)
      { lead_attributes: lead_attributes(facts), sincronizacao: estado.merge(facts).merge(conversation_id: conversation.id) }
    rescue ActiveRecord::ActiveRecordError => e
      raise SyncError, "sincronização pré-devolução indisponível (#{e.class})"
    end

    private

    attr_reader :lead

    # Lead sem conversa (ex.: assumido pelo card antes de qualquer contato) não tem mensagem a
    # sincronizar. Conversa apontada que não bate com o lead é divergência, não "nada a fazer".
    def resolve_conversation
      return nil if lead.upsales_conversation_atual_id.blank?

      conversation = ::Conversation.find_by(id: lead.upsales_conversation_atual_id, account_id: lead.conta_id)
      raise SyncError, 'conversa atual do lead não encontrada' if conversation.nil?
      raise SyncError, 'conversa atual pertence a outro contato' unless same_contact?(conversation)

      conversation
    end

    def same_contact?(conversation)
      return conversation.contact_id == lead.upsales_contact_id if lead.upsales_contact_id.present?

      phone = conversation.contact&.phone_number
      phone.present? && OperationalEngine::LeadRepository.find_by_telefone(conta_id: lead.conta_id, telefone: phone)&.lead_id == lead.lead_id
    end

    def message_facts(conversation)
      public_messages = conversation.messages.where(private: false, message_type: %i[incoming outgoing template])
      ultima_lead = public_messages.where(message_type: :incoming).reorder(:created_at, :id).last
      ultima_humana = public_messages.where(message_type: :outgoing, sender_type: 'User').reorder(:created_at, :id).last
      {
        ultima_mensagem_lead: message_ref(ultima_lead),
        ultima_mensagem_humana: message_ref(ultima_humana)&.merge(user_id: ultima_humana.sender_id),
        mensagens_na_intervencao: intervention_scope(public_messages).count
      }
    end

    def intervention_scope(scope)
      lead.modo_atendimento_entrou_em.present? ? scope.where('messages.created_at >= ?', lead.modo_atendimento_entrou_em) : scope
    end

    def message_ref(message)
      message && { message_id: message.id, timestamp: message.created_at.iso8601 }
    end

    # Só avança: uma fotografia mais nova já gravada nunca é trocada por uma mais antiga.
    def lead_attributes(facts)
      last_lead_at = facts.dig(:ultima_mensagem_lead, :timestamp)&.then { |ts| Time.zone.parse(ts) }
      return {} if last_lead_at.nil? || (lead.ultima_interacao_em.present? && lead.ultima_interacao_em >= last_lead_at)

      { ultima_interacao_em: last_lead_at }
    end

    # A fotografia com que a Lavínia volta (auditável pela timeline, sem consultar o lead depois).
    def estado
      {
        etapa_prospect: lead.etapa_prospect, qualificacao_status: lead.qualificacao_status,
        agendamento_status: lead.agendamento_status, frente_operacional: lead.frente_operacional,
        etapa_comercial: lead.etapa_comercial, resultado_comercial: lead.resultado_comercial,
        ultimo_ponto: lead.ultimo_ponto
      }
    end
  end
end
