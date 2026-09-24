# CP-11 (P1-VAL-08, P1-VAL-09; SSOT §22, Fase 10 do §27, testes 28.33–28.37 e 28.40): Dashboard
# Prospect por coorte, calculado sobre o Engine (Supabase) -- nunca sobre os cards Sales::Lead, que
# são projeção (§4) e existem em dobro (Prospect + Comercial) para o mesmo lead.
#
# Regras normativas aplicadas:
# - §22.2: a população é selecionada UMA vez (conta + entrada_operacao_em no período + filtros
#   oficiais) e todo indicador usa exatamente esses lead_id. Um lead de setembro que qualifica em
#   outubro continua na coorte de setembro (28.33).
# - §22.3: filtros oficiais SOMENTE período, modo (consolidado/outbound/inbound), origem_lead,
#   segmento e inbox_entrada_id. Modo de atendimento, responsável e recovery status NÃO entram.
# - §22.4/§22.5: um lead conta no máximo uma vez por marco (28.34) -- cada marco é um predicado
#   sobre a linha do lead, nunca uma contagem de eventos. Convertidos = conversao_em (write-once,
#   §16.5), então callback + reunião no mesmo lead contam uma vez (28.35).
# - §22.6: média aritmética só sobre quem atingiu o endpoint -- ausente não é zero (28.36).
# - §22.7: recovery como seção secundária, sobre os eventos da taxonomia §7.4.
#
# "Em conversa" não tem campo próprio no §6.1. O instante é derivado de fatos gravados: inbound
# nasce em Em conversa na entrada (§8.1, §11.2 -- por isso Iniciaram pode ser igual a Em conversa,
# 28.37), outbound chega na primeira resposta (primeira_resposta_em, §11.3), com o evento
# etapa_alterada {para: em_conversa} (§7.3) como fonte complementar. Para o CONTADOR do marco, um
# lead que já está numa etapa posterior ou já qualificou/converteu também atingiu Em conversa
# (§8.1: funil universal ordenado, §8.3: etapa não regride) -- mas o tempo médio só usa o instante
# real, nunca um instante inventado.
module OperationalEngine
  class ProspectDashboardMetrics
    class InvalidFilterError < StandardError; end

    TIMEZONE = 'America/Sao_Paulo'.freeze
    MODOS = %w[consolidado outbound inbound].freeze
    ETAPAS_EM_CONVERSA_OU_ALEM = %w[em_conversa qualificado agendado].freeze
    TIPOS_CONVERSAO = %w[agendamento callback].freeze
    # §7.4, grupo "Recuperação".
    EVENTOS_RECOVERY = %w[
      recuperacao_iniciada recuperacao_mensagem_enviada recuperacao_email_enviado recuperacao_respondida recuperacao_esgotada
    ].freeze
    COLUNAS = %i[
      lead_id modo_entrada etapa_prospect recuperacao_status entrada_operacao_em primeira_resposta_em
      qualificado_em conversao_em tipo_conversao
    ].freeze
    LeadRow = Struct.new(*COLUNAS, keyword_init: true)

    # filtros: data_inicial, data_final (AAAA-MM-DD, obrigatórios), modo, origem_lead, segmento,
    # inbox_entrada_id -- exatamente os filtros oficiais do §22.3, nenhum outro é lido.
    def self.call(conta_id:, filtros:)
      new(conta_id: conta_id, filtros: filtros).call
    end

    # Valores que existem na conta para os filtros oficiais (§22.3) -- só para montar os seletores.
    def self.filter_options(conta_id:)
      base = OperationalEngine::Lead.where(conta_id: conta_id).where.not(entrada_operacao_em: nil)
      {
        origens_lead: base.where.not(origem_lead: nil).distinct.order(:origem_lead).pluck(:origem_lead),
        segmentos: base.where.not(segmento: nil).distinct.order(:segmento).pluck(:segmento),
        inbox_entrada_ids: base.where.not(inbox_entrada_id: nil).distinct.order(:inbox_entrada_id).pluck(:inbox_entrada_id)
      }
    end

    def initialize(conta_id:, filtros:)
      filtros = filtros.to_h.symbolize_keys
      @conta_id = conta_id
      @data_inicial = parse_date(filtros[:data_inicial], :data_inicial)
      @data_final = parse_date(filtros[:data_final], :data_final)
      raise InvalidFilterError, 'data_final anterior a data_inicial' if @data_final < @data_inicial

      @modo = parse_modo(filtros[:modo])
      @origem_lead = filtros[:origem_lead].presence
      @segmento = filtros[:segmento].presence
      @inbox_entrada_id = parse_inbox(filtros[:inbox_entrada_id])
    end

    def call
      leads = coorte
      eventos = eventos_por_lead
      em_conversa_em = leads.to_h { |lead| [lead.lead_id, instante_em_conversa(lead, eventos[lead.lead_id])] }

      {
        coorte: descricao_coorte,
        big_numbers: big_numbers(leads, em_conversa_em),
        funil: funil(leads, em_conversa_em),
        tempos_medios: tempos_medios(leads, em_conversa_em),
        recovery: recovery(leads, eventos)
      }
    end

    private

    # §22.2: a seleção da população acontece só aqui.
    def coorte_scope
      periodo = @data_inicial.in_time_zone(TIMEZONE)..@data_final.in_time_zone(TIMEZONE).end_of_day
      scope = OperationalEngine::Lead.where(conta_id: @conta_id, entrada_operacao_em: periodo)
      scope = scope.where(modo_entrada: @modo) unless @modo == 'consolidado'
      scope = scope.where(origem_lead: @origem_lead) if @origem_lead
      scope = scope.where(segmento: @segmento) if @segmento
      scope = scope.where(inbox_entrada_id: @inbox_entrada_id) if @inbox_entrada_id
      scope
    end

    def coorte
      coorte_scope.pluck(*COLUNAS).map { |values| LeadRow.new(**COLUNAS.zip(values).to_h) }
    end

    # Eventos só dos lead_id da coorte (subquery sobre o mesmo scope, nunca uma segunda seleção).
    def eventos_por_lead
      OperationalEngine::LeadEvent
        .where(lead_id: coorte_scope.select(:lead_id))
        .where("event_type IN (:recovery) OR (event_type = 'etapa_alterada' AND metadata->>'para' = 'em_conversa')",
               recovery: EVENTOS_RECOVERY)
        .pluck(:lead_id, :event_type, :event_at)
        .group_by(&:first)
    end

    def instante_em_conversa(lead, eventos)
      candidatos = [lead.primeira_resposta_em]
      candidatos << lead.entrada_operacao_em if lead.modo_entrada == 'inbound'
      candidatos.concat(Array(eventos).select { |_, tipo| tipo == 'etapa_alterada' }.map(&:last))
      candidatos.compact.min
    end

    def atingiu_em_conversa?(lead, em_conversa_em)
      em_conversa_em[lead.lead_id].present? || ETAPAS_EM_CONVERSA_OU_ALEM.include?(lead.etapa_prospect) ||
        lead.qualificado_em.present? || lead.conversao_em.present?
    end

    def marcos(leads, em_conversa_em)
      {
        iniciados: leads.size,
        em_conversa: leads.count { |lead| atingiu_em_conversa?(lead, em_conversa_em) },
        qualificados: leads.count { |lead| lead.qualificado_em.present? },
        convertidos: leads.count { |lead| lead.conversao_em.present? }
      }
    end

    # §22.4: denominador de todos os cards = total de leads da coorte.
    def big_numbers(leads, em_conversa_em)
      contagem = marcos(leads, em_conversa_em)
      total = contagem[:iniciados]
      {
        leads_iniciados: total,
        em_conversa: { absoluto: contagem[:em_conversa], taxa: taxa(contagem[:em_conversa], total) },
        qualificados: { absoluto: contagem[:qualificados], taxa: taxa(contagem[:qualificados], total) },
        convertidos: { absoluto: contagem[:convertidos], taxa: taxa(contagem[:convertidos], total) }
      }
    end

    # §22.5: quatro marcos, eficiência etapa a etapa; agendamento/callback só como detalhe.
    def funil(leads, em_conversa_em)
      contagem = marcos(leads, em_conversa_em)
      {
        etapas: [
          { marco: 'iniciaram', absoluto: contagem[:iniciados], eficiencia: nil },
          { marco: 'em_conversa', absoluto: contagem[:em_conversa], eficiencia: taxa(contagem[:em_conversa], contagem[:iniciados]) },
          { marco: 'qualificados', absoluto: contagem[:qualificados], eficiencia: taxa(contagem[:qualificados], contagem[:em_conversa]) },
          { marco: 'convertidos', absoluto: contagem[:convertidos], eficiencia: taxa(contagem[:convertidos], contagem[:qualificados]) }
        ],
        composicao_conversao: TIPOS_CONVERSAO.index_with do |tipo|
          leads.count { |lead| lead.conversao_em.present? && lead.tipo_conversao == tipo }
        end
      }
    end

    # §22.6: média aritmética; só entra quem atingiu o endpoint (e tem o início do intervalo).
    def tempos_medios(leads, em_conversa_em)
      {
        entrada_ate_em_conversa: media(leads) { |lead| [lead.entrada_operacao_em, em_conversa_em[lead.lead_id]] },
        em_conversa_ate_qualificacao: media(leads) { |lead| [em_conversa_em[lead.lead_id], lead.qualificado_em] },
        qualificacao_ate_conversao: media(leads) { |lead| [lead.qualificado_em, lead.conversao_em] },
        entrada_ate_conversao: media(leads) { |lead| [lead.entrada_operacao_em, lead.conversao_em] }
      }
    end

    def media(leads)
      intervalos = leads.filter_map do |lead|
        inicio, fim = yield(lead)
        fim - inicio if inicio && fim
      end
      return { media_segundos: nil, amostra: 0 } if intervalos.empty?

      { media_segundos: (intervalos.sum / intervalos.size).round, amostra: intervalos.size }
    end

    # §22.7: precisou = teve ciclo de recovery (qualquer evento do grupo Recuperação, ou recovery
    # ativa agora); recuperado = recuperacao_respondida; conversão após recovery = sequência
    # temporal (conversao_em depois da primeira recuperação), não atribuição causal.
    #
    # Denominadores (lacuna do §22.7) decididos em 24/09/2026 pela Stéphanie, por recomendação do
    # Igor: taxa_recovery = precisaram ÷ todos os leads da coorte; taxa_sucesso = recuperados ÷
    # precisaram.
    def recovery(leads, eventos)
      precisaram = leads.select { |lead| recovery_eventos(eventos, lead).any? || lead.recuperacao_status == 'ativa' }
      recuperados = precisaram.filter_map do |lead|
        primeira = recovery_eventos(eventos, lead).select { |_, tipo| tipo == 'recuperacao_respondida' }.map(&:last).min
        [lead, primeira] if primeira
      end
      {
        precisaram: precisaram.size,
        recuperados: recuperados.size,
        taxa_recovery: taxa(precisaram.size, leads.size),
        taxa_sucesso: taxa(recuperados.size, precisaram.size),
        conversoes_apos_recovery: recuperados.count { |lead, primeira| lead.conversao_em.present? && lead.conversao_em >= primeira }
      }
    end

    def recovery_eventos(eventos, lead)
      Array(eventos[lead.lead_id]).select { |_, tipo| EVENTOS_RECOVERY.include?(tipo) }
    end

    def taxa(numerador, denominador)
      return nil if denominador.zero?

      (numerador.to_f / denominador).round(4)
    end

    def descricao_coorte
      {
        data_inicial: @data_inicial.iso8601, data_final: @data_final.iso8601, timezone: TIMEZONE,
        modo: @modo, origem_lead: @origem_lead, segmento: @segmento, inbox_entrada_id: @inbox_entrada_id
      }
    end

    def parse_date(value, campo)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError
      raise InvalidFilterError, "#{campo} inválida (esperado AAAA-MM-DD)"
    end

    def parse_modo(value)
      modo = value.presence || 'consolidado'
      raise InvalidFilterError, "modo inválido: #{modo}" unless MODOS.include?(modo)

      modo
    end

    def parse_inbox(value)
      return nil if value.blank?

      Integer(value.to_s, 10)
    rescue ArgumentError
      raise InvalidFilterError, 'inbox_entrada_id inválido'
    end
  end
end
