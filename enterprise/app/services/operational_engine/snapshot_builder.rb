# Monta o Snapshot de entrada da Lavínia -- SSOT §12.3, S-4 do plano do Marco 1. Espelha
# `leadSnapshotSchema` (up2-agents, `src/modules/operational-engine/contracts.ts`) campo a campo:
# qualquer mudança de forma tem que mudar os dois lados juntos, são o mesmo contrato em dois
# repositórios. Só o "estado operacional" -- histórico de mensagens e a mensagem atual são
# montados pelo próprio up2-agents (checkpointer do LangGraph + webhook do Chatwoot), não
# passam por aqui: "não despejar toda a tabela, todo o histórico... em todo turno" (§12.3).
module OperationalEngine
  class SnapshotBuilder
    CONTRACT_VERSION = 1

    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    def call
      {
        contract_version: CONTRACT_VERSION,
        identidade: identidade,
        aquisicao: aquisicao,
        estado: estado,
        conhecimento: conhecimento,
        continuidade: continuidade,
        source: 'engine'
      }
    end

    private

    attr_reader :lead

    def identidade
      {
        lead_id: lead.lead_id,
        nome: lead.nome,
        empresa: lead.empresa,
        telefone: lead.telefone,
        segmento: lead.segmento,
        regiao: lead.regiao
      }
    end

    def aquisicao
      {
        origem_lead: lead.origem_lead,
        modo_entrada: lead.modo_entrada,
        tipo_entrada: lead.tipo_entrada,
        inbox_entrada_id: lead.inbox_entrada_id&.to_s,
        inbox_atual_id: lead.inbox_atual_id&.to_s
      }
    end

    def estado
      {
        etapa_prospect: lead.etapa_prospect,
        qualificacao_status: lead.qualificacao_status,
        orcamento_status: lead.orcamento_status,
        agendamento_status: lead.agendamento_status,
        recuperacao_status: lead.recuperacao_status,
        frente_operacional: lead.frente_operacional,
        modo_atendimento: lead.modo_atendimento,
        nao_contatar: lead.nao_contatar
      }
    end

    def conhecimento
      {
        modelo_atual: lead.modelo_atual,
        dor_oportunidade: lead.dor_oportunidade,
        impacto: lead.impacto,
        intencao_comercial: lead.intencao_comercial,
        cep: lead.cep,
        cobertura_status: lead.cobertura_status,
        volume_mensal_kg: lead.volume_mensal_kg&.to_f,
        retiradas_semana: lead.retiradas_semana
      }
    end

    def continuidade
      {
        ultimo_ponto: lead.ultimo_ponto,
        resumo_oportunidade: lead.resumo_oportunidade,
        ultima_interacao_em: lead.ultima_interacao_em&.iso8601,
        contexto_execucao: contexto_execucao
      }
    end

    # Não é coluna do lead -- é lido do estado atual (§12.3: "conversa|primeiro_contato|
    # recuperacao|agenda"). Hoje só existe chamador para o turno inbound (mensagem do lead
    # chegando), então "conversa" é o valor honesto na esmagadora maioria dos casos; as duas
    # exceções que já são decidíveis a partir do lead sozinho ficam explícitas. "primeiro_contato"
    # e a semântica completa de "recuperacao" pertencem ao dispatcher outbound (Fase 6/§10.5, que
    # ainda não chama este builder) e não são simuladas aqui.
    def contexto_execucao
      return 'agenda' if lead.agendamento_status_em_andamento?
      return 'recuperacao' if lead.recuperacao_status_ativa? && lead.etapa_prospect_contatado?

      'conversa'
    end
  end
end
