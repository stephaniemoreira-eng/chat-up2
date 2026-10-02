# Card de CRM e uma representação visual do Operational Engine. Quando um card nativo entra
# no Backlog do funil Prospecção, esta é a fronteira explícita de entrada: cria a fotografia
# operacional uma única vez e pede a projeção que vincula o próprio card existente.
#
# Não faz o caminho inverso de SalesProjectionSync. Depois da criação, o Engine permanece a
# fonte de verdade; reenviar um card já associado ou encontrar o mesmo telefone nunca regride
# uma conversa/qualificação existente para Backlog.
module OperationalEngine
  class BacklogIntake
    EXTERNAL_SOURCE = 'crm_backlog'.freeze

    def self.call(sales_lead:)
      new(sales_lead:).call
    end

    def initialize(sales_lead:)
      @sales_lead = sales_lead
    end

    def call
      return unless eligible?
      return unless telefone

      lead = OperationalEngine::LeadRepository.find_by_telefone(conta_id: account.id, telefone: telefone)
      lead ? register_existing(lead) : create_lead
    end

    private

    def eligible?
      @sales_lead.operational_lead_id.blank? &&
        @sales_lead.pipeline.engine_kind == Sales::Pipelines::SeedProspectPipelineService::ENGINE_KIND &&
        @sales_lead.stage.engine_stage_key == 'backlog'
    end

    def create_lead
      lead = OperationalEngine::LeadRepository.find_or_create_by_telefone(
        conta_id: account.id,
        telefone: telefone,
        attributes: lead_attributes
      )

      lead.with_lock do
        write_event(lead, 'lead_criado')
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'entrada_crm_backlog')
      end
      OperationalEngine::ProjectionReconciler.flush(lead)
      lead
    end

    def register_existing(lead)
      lead.with_lock do
        lead.update!(upsales_contact_id: contact.id) if lead.upsales_contact_id.nil?
        write_event(lead, 'nova_entrada')
        OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'entrada_crm_backlog')
      end
      OperationalEngine::ProjectionReconciler.flush(lead)
      lead
    end

    def write_event(lead, event_type)
      OperationalEngine::EventWriter.call(
        lead: lead,
        event_type: event_type,
        source: 'human',
        external_source: EXTERNAL_SOURCE,
        external_id: @sales_lead.id.to_s,
        metadata: dados_origem
      )
    end

    def lead_attributes
      {
        nome: contact.name,
        empresa: @sales_lead.title,
        origem_lead: 'crm_backlog_manual',
        modo_entrada: 'outbound',
        tipo_entrada: 'manual',
        relacao_atual: 'prospect',
        etapa_prospect: 'backlog',
        etapa_entrou_em: Time.current,
        lead_status: 'ativo',
        frente_operacional: 'prospeccao',
        dados_origem: dados_origem,
        upsales_contact_id: contact.id
      }
    end

    def dados_origem
      {
        fonte: EXTERNAL_SOURCE,
        sales_lead_id: @sales_lead.id,
        sales_pipeline_id: @sales_lead.sales_pipeline_id,
        sales_stage_id: @sales_lead.sales_stage_id
      }
    end

    def account
      @account ||= @sales_lead.account
    end

    def contact
      @contact ||= @sales_lead.contact
    end

    def telefone
      @telefone ||= Sales::Prospecting::PhoneNormalizer.normalize(contact.phone_number)
    end
  end
end
