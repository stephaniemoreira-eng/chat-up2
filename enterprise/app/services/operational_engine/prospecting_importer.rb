# Primeira fonte outbound a alimentar o Engine (§3.1 item 1 e §10.1, "entrada no Backlog"): a
# Busca/Prospecção acha a empresa no Google Places, e o lead precisa nascer no Supabase, em
# Backlog, pra existir pro FIFO, pro dispatcher e pro Dashboard. Até aqui o único caminho que
# criava lead no Engine era o inbound (Fase 3) -- um lead achado na busca existia só como
# Sales::Lead, card no Kanban, invisível pro funil operacional.
#
# A criação deste serviço termina no Engine. O chamador só pode criar o card depois, usando
# SalesProjectionSync, que aponta para o pipeline canônico de Prospecção. Inverter essa ordem
# faria existir um Sales::Lead sem estado de negócio no Supabase (§3.3/§4).
module OperationalEngine
  class ProspectingImporter
    EXTERNAL_SOURCE = 'upsales_prospecting'.freeze

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
      lead = OperationalEngine::IdempotencyGuard.call(
        conta_id: conta_id,
        event_type: 'busca_importada',
        external_source: EXTERNAL_SOURCE,
        external_id: @result.id.to_s
      ) { importar }

      # Uma nova tentativa depois de o Engine já ter persistido o fato não deve parecer "vazia"
      # para o chamador: ele ainda pode (e deve) reparar a projeção visual que tenha falhado.
      lead || OperationalEngine::LeadRepository.find_by_telefone(conta_id: conta_id, telefone: telefone)
    end

    private

    def importar
      # find_by_telefone antes de criar, mesmo motivo do InboundProcessor: o find_or_create
      # sozinho evitaria o registro duplicado, mas não os eventos espúrios -- `lead_criado` não
      # pode ser escrito pra um lead que já existia.
      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: conta_id, telefone: telefone)

      return criar_em_backlog unless lead

      imported_by_this_result?(lead) ? registrar_criacao_interrompida(lead) : registrar_nova_ocorrencia(lead)
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
    # `cliente_atual`/`nao_contatar` são checados na seleção do Backlog (§10.2), não aqui.
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
      lead
    end

    # Se a primeira execução criou a linha `leads`, mas caiu antes de gravar seu evento, o retry
    # deve terminar o fato original `lead_criado`, não inventar uma segunda entrada de origem.
    def registrar_criacao_interrompida(lead)
      write_event(lead, 'lead_criado')
      lead
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
    # Engine: `leads.telefone` é NOT NULL e é a própria chave de dedupe (§5.1). Sem estado no
    # Engine não se cria card no CRM; o resultado pode ser enriquecido e reprocessado depois.
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

    def imported_by_this_result?(lead)
      lead.dados_origem['prospecting_result_id'].to_s == @result.id.to_s
    end
  end
end
