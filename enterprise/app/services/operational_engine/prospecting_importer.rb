# Primeira fonte outbound a alimentar o Engine (§3.1 item 1 e §10.1, "entrada no Backlog"): a
# Busca/Prospecção acha a empresa no Google Places, e o lead precisa nascer no Supabase, em
# Backlog, pra existir pro FIFO, pro dispatcher e pro Dashboard. Até aqui o único caminho que
# criava lead no Engine era o inbound (Fase 3) -- um lead achado na busca existia só como
# Sales::Lead, card no Kanban, invisível pro funil operacional.
#
# Não chama SalesProjectionSync de propósito: quem chama este importador
# (Sales::Prospecting::CreateLeadsFromResultsService) já criou o Sales::Lead no pipeline/coluna
# que a pessoa escolheu na tela da busca. Rodar a projeção aqui não acrescentaria card nenhum e
# ainda arriscaria renomear um Sales::Lead anterior do mesmo contato -- e o mapa
# etapa_prospect -> stage do Kanban é decisão da Fase 5 (§32).
module OperationalEngine
  class ProspectingImporter
    EXTERNAL_SOURCE = 'upsales_prospecting'.freeze
    # CP-09 (P2-VAL-06): etapas do ciclo de prospecção fria -- ver encerrar_cliente_atual.
    ETAPAS_PROSPECCAO_FRIA = %w[backlog contatado].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(result:, contact:, auto_contact_enabled: false, contact_tag: nil)
      @result = result
      @contact = contact
      @auto_contact_enabled = auto_contact_enabled
      @contact_tag = contact_tag
    end

    def call
      return if telefone.blank?

      # Idempotência do import inteiro -- teste 28.9 aplicado à busca. Reprocessar o MESMO
      # Sales::ProspectingResult não pode virar um `nova_entrada` dizendo que o lead foi achado
      # outra vez; a ocorrência nova de verdade (a mesma empresa reencontrada numa busca
      # posterior) chega com outro id de resultado e passa direto por aqui.
      OperationalEngine::IdempotencyGuard.call(
        conta_id: conta_id,
        event_type: 'busca_importada',
        external_source: EXTERNAL_SOURCE,
        external_id: @result.id.to_s
      ) { importar }
    end

    private

    def importar
      # find_by_telefone antes de criar, mesmo motivo do InboundProcessor: o find_or_create
      # sozinho evitaria o registro duplicado, mas não os eventos espúrios -- `lead_criado` não
      # pode ser escrito pra um lead que já existia.
      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: conta_id, telefone: telefone)

      lead ? registrar_nova_ocorrencia(lead) : criar_em_backlog
    end

    def criar_em_backlog
      lead = OperationalEngine::LeadRepository.find_or_create_by_telefone(
        conta_id: conta_id,
        telefone: telefone,
        attributes: atributos_de_entrada
      )

      write_event(lead, 'lead_criado')
      lead
    end

    # Vocabulário congelado do §5.2: `google_scraping` é a origem de quem veio de busca no Google,
    # e `prospect` é a fotografia atual de uma empresa que ainda não tem relação com o cliente --
    # `cliente_atual`/`nao_contatar` são checados na seleção do Backlog (§10.2). Um lead que JÁ
    # existe como cliente atual tem o ciclo Prospect encerrado em `encerrar_cliente_atual` (CP-09).
    def atributos_de_entrada
      {
        empresa: @result.name,
        origem_lead: 'google_scraping',
        modo_entrada: 'outbound',
        tipo_entrada: 'novo',
        relacao_atual: 'prospect',
        # §10.1 termina em "ainda não preencher entrada_operacao_em": Backlog é estoque, não
        # oportunidade iniciada. Esse timestamp (e primeiro_contato_em) só existem depois de
        # envio real confirmado pelo provedor -- §10.6 e teste 28.1, Fase 6.
        etapa_prospect: 'backlog',
        # Obrigatório, não decorativo: o FIFO do Backlog ordena por etapa_entrou_em ASC (§10.3).
        etapa_entrou_em: Time.current,
        lead_status: 'ativo',
        frente_operacional: 'prospeccao',
        segmento: segmento,
        regiao: regiao,
        dados_origem: dados_origem,
        upsales_contact_id: @contact.id
      }
    end

    # §5.4 e teste 28.8: o lead já existe (entrou pelo inbound, ou por uma busca anterior). Não
    # duplica, não sobrescreve origem_lead (write-once, garantido por trigger no banco) e não
    # mexe em etapa -- um lead que já está em conversa não volta pro Backlog só por ter sido
    # achado de novo numa lista. Registra a ocorrência e para por aí.
    def registrar_nova_ocorrencia(lead)
      # Back-reference técnica (§6.1), não estado de negócio: só preenche o que está vazio.
      lead.update!(upsales_contact_id: @contact.id) if lead.upsales_contact_id.nil?

      write_event(lead, 'nova_entrada', **dados_origem)
      encerrar_cliente_atual(lead)
      lead
    end

    # CP-09 (P2-VAL-06; SSOT §19.1, teste 28.24): lead achado na busca que já é cliente atual não é
    # prospectado E tem o ciclo Prospect encerrado como `cliente_atual` -- antes ficava ativo em
    # Backlog para sempre, só excluído da fila pelo BacklogSelector.
    #
    # Escopo estreito de propósito: só o ciclo de prospecção fria (frente Prospecção, Backlog ou
    # Contatado). Um cliente atual em conversa (Em conversa em diante) ou com oportunidade na frente
    # Comercial tem interação real que o §19.1 permite responder/encaminhar -- encerrar isso por
    # causa de uma lista de scraping não é regra do SSOT. Sob lock (estado relido): o importador
    # pode correr junto com o inbound do mesmo contato.
    def encerrar_cliente_atual(lead)
      lead.with_lock do
        next unless cliente_atual_em_prospeccao_fria?(lead)

        transicao = { de: lead.lead_status, para: 'encerrado', motivo: 'cliente_atual',
                      motivo_encerramento_de: lead.motivo_encerramento, motivo_encerramento: 'cliente_atual' }
        lead.update!(lead_status: 'encerrado', motivo_encerramento: 'cliente_atual')
        write_event(lead, 'lead_encerrado', **transicao)
      end
    end

    def cliente_atual_em_prospeccao_fria?(lead)
      lead.relacao_atual == 'cliente_atual' && lead.lead_status_ativo? &&
        lead.frente_operacional_prospeccao? && ETAPAS_PROSPECCAO_FRIA.include?(lead.etapa_prospect)
    end

    # external_id é o id do Sales::ProspectingResult, não o place_id: cada execução da busca grava
    # sua própria linha de resultado, então reprocessar o MESMO resultado é idempotente (28.9),
    # enquanto a mesma empresa reencontrada numa busca posterior é uma ocorrência nova de verdade
    # -- que é justamente o que o 28.8 manda registrar.
    def write_event(lead, event_type, **metadata)
      OperationalEngine::EventWriter.call(
        lead: lead,
        event_type: event_type,
        source: 'import',
        external_source: EXTERNAL_SOURCE,
        external_id: @result.id.to_s,
        metadata: metadata
      )
    end

    def conta_id
      @result.account_id
    end

    # Contact#phone_number já vem em E.164 (a busca normaliza antes de criar o contato), mas
    # resultado do Places sem telefone vira contato sem telefone -- e sem telefone não há lead no
    # Engine: `leads.telefone` é NOT NULL e é a própria chave de dedupe (§5.1). O card no Kanban
    # continua existindo e pode ser enriquecido depois.
    def telefone
      @telefone ||= Sales::Prospecting::PhoneNormalizer.normalize(@contact.phone_number)
    end

    def search
      @search ||= @result.search
    end

    def segmento
      search.business_type
    end

    # §6.1: `regiao` é "região/cidade operacional" -- a cidade que a busca mirou, não o endereço
    # bruto do resultado (esse fica em dados_origem). Cobertura real (`cobertura_status`, `cep`)
    # é decisão de negócio de fase posterior, a partir do CEP, não daqui.
    def regiao
      [search.neighborhood.presence, "#{search.city}/#{search.state}"].compact.join(' - ')
    end

    # §5.4: o que é específico da aquisição fica aqui enquanto não justificar coluna própria. O
    # SCAN ainda não rodou neste ponto (ScanResultJob é enfileirado depois da criação do lead),
    # então score/faixa não entram aqui -- quando entrarem, o evento é `lead_enriquecido` (§7.4).
    def dados_origem
      {
        fonte: 'busca_prospeccao',
        place_id: @result.place_id,
        endereco: @result.address,
        website: @result.website,
        rating: @result.rating&.to_f,
        avaliacoes: @result.user_ratings_total,
        prospecting_search_id: @result.sales_prospecting_search_id,
        prospecting_result_id: @result.id,
        auto_contact_enabled: @auto_contact_enabled,
        contact_tag: @contact_tag
      }.compact
    end
  end
end
