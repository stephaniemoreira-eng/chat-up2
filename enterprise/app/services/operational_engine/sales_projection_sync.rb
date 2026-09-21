# §5.2/§5.3: Sales::Lead é projeção visual, nunca fonte de verdade -- esta é a ÚNICA direção
# permitida (Supabase → Sales::*). Nunca chame isto a partir de um controller/tela do UpSales.
#
# Fase 5 (§8.1, §20.1, §21.1): mantém o card no pipeline dedicado do funil Prospect (não o
# "Comercial" genérico) sincronizado com `etapa_prospect`, e as tags LAVÍNIA/HUMANO/CALLBACK
# derivadas de `modo_atendimento`/`agendamento_status`. Mover etapa passa por
# Sales::Leads::MoveStageService com `user: nil` de propósito -- é o mesmo sinal que o serviço
# usa pra permitir a única forma legítima de um card chegar em Agendado (§21.2, ver o comentário
# em move_stage_service.rb), e dá de graça o registro em Sales::StageTransition + os eventos
# SALES_LEAD_STAGE_CHANGED que um `save!` direto no card não geraria.
#
# `frente_operacional`/etapa_comercial (Kanban Comercial, §8.4) ficam fora daqui -- Fase 9, board
# e pipeline separados.
module OperationalEngine
  class SalesProjectionSync
    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    def call
      return unless contact

      existing ? sync(existing) : create
    end

    private

    def existing
      @existing ||= Sales::Lead.find_by(account_id: @lead.conta_id, contact_id: @lead.upsales_contact_id, sales_pipeline_id: pipeline.id)
    end

    def create
      sales_lead = Sales::Lead.new(contact: contact, pipeline: pipeline, stage: target_stage, title: title)
      sales_lead.custom_attributes = sales_lead.custom_attributes.merge('engine_tags' => computed_tags)
      sales_lead.save!
      sales_lead
    end

    def sync(sales_lead)
      if sales_lead.sales_stage_id != target_stage.id
        Sales::Leads::MoveStageService.new(lead: sales_lead, stage: target_stage, user: nil).perform
      end

      sales_lead.update!(title: title, custom_attributes: sales_lead.custom_attributes.merge('engine_tags' => computed_tags))
      sales_lead
    end

    # bang de propósito: as cinco stages nascem juntas em SeedProspectPipelineService, então uma
    # ausência aqui não é "ainda não sincronizado", é uma stage canônica apagada por engano -- tem
    # que estourar alto, não silenciar caindo pra qualquer outra coluna.
    def target_stage
      @target_stage ||= pipeline.stages.find_by!(engine_stage_key: @lead.etapa_prospect)
    end

    def pipeline
      @pipeline ||= Sales::Pipelines::SeedProspectPipelineService.new(account: account).perform
    end

    # §20.1: LAVÍNIA/HUMANO são mutuamente exclusivas (o card sempre tem uma das duas); CALLBACK é
    # aditiva. NO-SHOW e a propensão FRIO/MORNO/QUENTE são do Kanban Comercial (§20.2/§20.3) --
    # Fase 9, não computadas aqui.
    def computed_tags
      tags = [@lead.modo_atendimento == 'humano' ? 'humano' : 'lavinia']
      tags << 'callback' if @lead.agendamento_status == 'callback_registrado'
      tags
    end

    def title
      @lead.empresa.presence || @lead.nome.presence || @lead.telefone
    end

    def contact
      @contact ||= Contact.find_by(id: @lead.upsales_contact_id, account_id: @lead.conta_id)
    end

    def account
      @account ||= Account.find(@lead.conta_id)
    end
  end
end
