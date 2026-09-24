# CP-09 (P1-VAL-04, P1-VAL-05; SSOT §8.4, §16.1, §16.2, §17.2, §7.4): "criar/manter oportunidade
# Comercial" num lugar só. Antes do CP-09 cada caminho fazia isso do seu jeito: o handoff (CP-05)
# gravava `etapa_comercial = oportunidade` + evento `oportunidade_criada`; o callback só gravava a
# etapa, sem evento; a reunião confirmada não criava nada.
#
# Regra (idêntica à do handoff):
# - cria (`etapa_comercial = oportunidade`) só quando ainda não havia oportunidade -- §8.4: "antes de
#   existir oportunidade, etapa_comercial = null";
# - mantém: nunca rebaixa uma oportunidade que já avançou (em_acompanhamento/ganho/perdido);
# - `oportunidade_criada` só quando a oportunidade nasce de fato.
#
# NÃO mexe em frente_operacional, modo_atendimento nem responsável: isso é o handoff real (§17.2),
# decisão separada. Callback registrado e reunião confirmada abrem a oportunidade sem tirar a
# Lavínia da conversa.
#
# Tem que ser chamado DENTRO do `lead.with_lock` de quem chama: não abre transação própria.
module OperationalEngine
  module ComercialOpportunity
    EVENT_TYPE = 'oportunidade_criada'.freeze

    # Retorna true se a oportunidade foi criada agora.
    def self.garantir!(lead, source:, motivo:, correlation_id: SecureRandom.uuid)
      return false if lead.etapa_comercial.present?

      lead.update!(etapa_comercial: 'oportunidade')
      registrar_evento!(lead, source: source, motivo: motivo, correlation_id: correlation_id)
      true
    end

    # Formato único do evento, usado também pelo HandoffToCommercialService (que grava a etapa junto
    # com as outras dimensões do §17.2 num único update).
    def self.registrar_evento!(lead, source:, motivo:, correlation_id:)
      OperationalEngine::LeadEvent.create!(
        lead: lead, event_type: EVENT_TYPE, source: source,
        metadata: { etapa_comercial: lead.etapa_comercial, motivo: motivo, correlation_id: correlation_id }
      )
    end
  end
end
