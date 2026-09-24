# Monta o Snapshot de entrada da Lavínia -- SSOT §12.3, S-4 do plano do Marco 1. Espelha
# `leadSnapshotSchema` (up2-agents, `src/modules/operational-engine/contracts.ts`) campo a campo:
# qualquer mudança de forma tem que mudar os dois lados juntos, são o mesmo contrato em dois
# repositórios.
#
# CP-03 (P1-017-01/P1-017-02/P1-021-03/P1-022-02): o Snapshot agora é do TURNO, não só do lead --
# quem conhece o disparador (o orquestrador) informa `contexto_execucao` e a mensagem que disparou
# o turno; o Engine resolve `mensagem_atual` e `mensagens_recentes_relevantes` em torno dela
# (OperationalEngine::TurnMessages) e valida a coerência. O contexto não é mais inferido da
# fotografia do lead: o mesmo estado produz contextos diferentes conforme o gatilho.
module OperationalEngine
  class SnapshotBuilder
    CONTRACT_VERSION = 1
    CONTEXTOS = %w[conversa primeiro_contato recuperacao agenda].freeze
    CONTEXTO_PADRAO = 'conversa'.freeze

    # trigger: { contexto_execucao:, mensagem_atual:, mensagens_recentes_relevantes: } (ver
    # SnapshotController). Sem trigger (chamador legado) = conversa sem mensagem resolvida.
    def self.call(lead, trigger: {})
      new(lead, trigger).call
    end

    def initialize(lead, trigger = {})
      @lead = lead
      @trigger = trigger || {}
    end

    def call
      {
        contract_version: CONTRACT_VERSION,
        identidade: identidade,
        aquisicao: aquisicao,
        estado: estado,
        conhecimento: conhecimento,
        continuidade: continuidade,
        mensagens_recentes_relevantes: @trigger[:mensagens_recentes_relevantes] || [],
        mensagem_atual: @trigger[:mensagem_atual],
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

    def contexto_execucao
      @trigger[:contexto_execucao].presence || CONTEXTO_PADRAO
    end
  end
end
