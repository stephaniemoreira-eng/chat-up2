# SSOT §13.3 -- persistência de "qualificado" num lugar só. Usado pela rota curta de agendamento
# (CP-04, P1-018-03: intenção explícita de agendar é evidência suficiente, §13.2) e pelo commit da
# saída estruturada da Lavínia (CP-03, decisao_qualificacao=qualificado) -- duas regras iguais em
# dois serviços divergiriam.
#
# Tem que ser chamado DENTRO do `lead.with_lock` de quem chama: não abre transação própria.
#
# - qualificacao_status = qualificado;
# - qualificado_em só na primeira ocorrência;
# - etapa_prospect avança para qualificado (com etapa_entrou_em) somente a partir de uma etapa
#   anterior -- nunca regride um Agendado (§8.3: nada reduz etapa automaticamente);
# - eventos lead_qualificado (só quando o status muda) e etapa_alterada (só quando a etapa muda).
module OperationalEngine
  class QualificationService
    ETAPAS_ANTERIORES = %w[backlog contatado em_conversa].freeze

    def self.qualificar!(lead, source:)
      new(lead, source).qualificar!
    end

    def initialize(lead, source)
      @lead = lead
      @source = source
    end

    # Retorna true se algo mudou.
    def qualificar!
      now = Time.current
      status_changed = !@lead.qualificacao_status_qualificado?
      etapa_anterior = @lead.etapa_prospect
      move_etapa = ETAPAS_ANTERIORES.include?(etapa_anterior)
      return false unless status_changed || move_etapa

      @lead.update!(
        qualificacao_status: 'qualificado',
        **(@lead.qualificado_em.nil? ? { qualificado_em: now } : {}),
        **(move_etapa ? { etapa_prospect: 'qualificado', etapa_entrou_em: now } : {})
      )
      write_event('lead_qualificado') if status_changed
      write_event('etapa_alterada', de: etapa_anterior, para: 'qualificado') if move_etapa
      true
    end

    private

    def write_event(event_type, **metadata)
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: event_type, source: @source,
        metadata: metadata.merge(correlation_id: SecureRandom.uuid)
      )
    end
  end
end
