# CP-01 (P0-024-01, P0-022-02): UMA definição do que torna um lead abordável pela primeira
# abordagem outbound agora (SSOT §10.2, §19.1, §19.2, §23.2). Usada em dois momentos que antes
# checavam coisas diferentes:
#
# 1. Dispatcher#still_eligible? -- releitura sob lock logo depois da seleção do BacklogSelector;
# 2. OutboundSendGate -- releitura sob lock no instante em que a mensagem de abertura vai ser
#    gravada (o post público), que é a autorização que de fato vale.
#
# O BacklogSelector continua com o próprio `where` (é uma query, não um objeto carregado), mas os
# fatos têm que ser os mesmos daqui. Telefone normalizado válido fica com o CP-02 (P1-024-04).
#
# Retorna a lista de motivos que BLOQUEIAM -- vazia = elegível. Motivos em texto fixo (não i18n):
# vão pra log e pra resposta HTTP ao up2-agents, nunca pro cliente.
module OperationalEngine
  class OutboundEligibility
    def self.origination_blockers(lead)
      new(lead).origination_blockers
    end

    def initialize(lead)
      @lead = lead
    end

    def origination_blockers
      [].tap do |blockers|
        blockers << 'nao_contatar' if @lead.nao_contatar?
        blockers << 'cliente_atual' if @lead.relacao_atual == 'cliente_atual'
        blockers << 'lead_encerrado' unless @lead.lead_status_ativo?
        blockers << 'atendimento_humano' unless @lead.modo_atendimento_lavinia?
        blockers << 'fora_do_backlog' unless @lead.etapa_prospect_backlog?
        # §10.2 "não possuir primeira abordagem já enviada no ciclo": outra ativação já foi
        # confirmada pelo provider (ConfirmOutboundSendService grava isso) -- a atual chegou tarde.
        blockers << 'primeira_abordagem_ja_enviada' if @lead.primeiro_contato_em.present?
      end
    end
  end
end
