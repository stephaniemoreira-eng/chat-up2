# CP-13 (P1-VAL-12; SSOT §15.8, §19.1, §19.2, §23.2, §28.23, §28.25): UMA definição de "esta
# tentativa de recovery ainda pode sair agora". Usada em dois momentos, sempre sob o lock do lead:
#
# 1. RecoveryDispatcher -- antes de autorizar/executar a tentativa (e, se bloqueada, o ciclo é
#    interrompido: timer que não faz mais sentido não fica pendurado);
# 2. OutboundSendGate -- no instante do post público da mensagem de recovery (a autorização que de
#    fato vale, porque entre o dispatcher e o post existem LLM e rede).
#
# Retorna os motivos que BLOQUEIAM (vazio = pode). Texto fixo, só para log/evento/HTTP.
#
# Decisões registradas no PR:
# - "nenhum handoff incompatível": frente Comercial ou motivo_handoff preenchido -- recovery é
#   trabalho da Prospecção/Lavínia; depois do handoff o dono é o Comercial;
# - "inbox atual compatível" (§5.3.1: recoveries continuam na mesma conversa/inbox do ciclo): a
#   conversa do ciclo precisa ser WhatsApp e estar na inbox atual do lead (ou, sem inbox_atual_id --
#   lead outbound que nunca respondeu --, na inbox de Prospecção configurada);
# - "nenhuma resposta nova": a última mensagem pública da conversa é do contato.
module OperationalEngine
  class RecoveryEligibility
    def self.blockers(lead, conversation:, agent_tenant:)
      new(lead, conversation, agent_tenant).blockers
    end

    # A conversa do ciclo: onde a mensagem que deixou o lead aguardando foi enviada
    # (RecoveryCycle.arm! grava upsales_conversation_atual_id nesse momento).
    def self.conversation_for(lead)
      return nil if lead.upsales_conversation_atual_id.blank?

      ::Conversation.find_by(id: lead.upsales_conversation_atual_id, account_id: lead.conta_id)
    end

    def initialize(lead, conversation, agent_tenant)
      @lead = lead
      @conversation = conversation
      @agent_tenant = agent_tenant
    end

    def blockers
      protection_blockers + state_blockers + conversation_blockers
    end

    private

    def protection_blockers
      [].tap do |blockers|
        blockers << 'lead_encerrado' unless @lead.lead_status_ativo?
        blockers << 'nao_contatar' if @lead.nao_contatar?
        blockers << 'cliente_atual' if @lead.relacao_atual == 'cliente_atual'
      end
    end

    def state_blockers
      [].tap do |blockers|
        blockers << 'atendimento_humano' unless @lead.modo_atendimento_lavinia?
        blockers << 'nao_aguarda_resposta' unless @lead.aguardando_resposta?
        blockers << 'handoff_incompativel' if @lead.frente_operacional_comercial? || @lead.motivo_handoff.present?
        blockers << 'sem_recuperacao_agendada' if @lead.proxima_recuperacao_em.nil?
      end
    end

    def conversation_blockers
      return ['conversa_indisponivel'] unless conversation_of_lead?
      return ['inbox_incompativel'] unless inbox_compatible?
      return ['resposta_nova'] if contact_spoke_last?

      []
    end

    # A conversa vem de upsales_conversation_atual_id (gravado pelo próprio Engine ao armar o ciclo ou
    # no inbound), escopada pela conta. Não compara contact_id: o contato do importador e o da
    # conversa podem ser registros diferentes para o mesmo telefone (RISK-019-02).
    def conversation_of_lead?
      @conversation.present? && @conversation.account_id == @lead.conta_id
    end

    def inbox_compatible?
      return false unless @conversation.inbox&.channel_type == 'Channel::Whatsapp'

      expected = @lead.inbox_atual_id.presence || @agent_tenant&.whatsapp_inbox_id
      expected.present? && expected.to_i == @conversation.inbox_id
    end

    def contact_spoke_last?
      last = @conversation.messages.where(private: false, message_type: %i[incoming outgoing template]).reorder(id: :desc).first
      last&.incoming? || false
    end
  end
end
