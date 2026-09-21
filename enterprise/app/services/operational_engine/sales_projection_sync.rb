# §5.2/§5.3: Sales::Lead é projeção visual, nunca fonte de verdade -- esta é a ÚNICA direção
# permitida (Supabase → Sales::*). Nunca chame isto a partir de um controller/tela do UpSales.
#
# Fase 5 (§8.1, §20.1, §21.1): mantém o card no pipeline dedicado do funil Prospect (não o
# "Comercial" genérico) sincronizado com `etapa_prospect`, as tags LAVÍNIA/HUMANO/CALLBACK
# derivadas de `modo_atendimento`/`agendamento_status`, e os sete campos que alimentam os
# filtros do Kanban (§21.1) em `custom_attributes['engine_filters']`. Mover etapa passa por
# Sales::Leads::MoveStageService com `system_source: :operational_engine` de propósito. Antes de
# chegar aqui, OperationalEngine::Lead e a constraint no Supabase já validam que Agendado tem
# Calendar confirmado, id real e timestamp (§16.1/§21.2). Isso mantém o caminho privilegiado
# restrito à projeção de um fato persistido e ainda gera Sales::StageTransition.
#
# `etapa_comercial` (Kanban Comercial, §8.4) fica fora daqui de propósito -- board e pipeline
# separados, ver OperationalEngine::ComercialProjectionSync.
module OperationalEngine
  class SalesProjectionSync
    class ProjectionIntegrityError < StandardError; end
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
      @existing ||= begin
        mapped = mapped_projection_scope.find_by(operational_lead_id: @lead.lead_id)
        if mapped
          mapped
        else
          # Cards das versões anteriores não carregavam o vínculo técnico. Podemos adotá-los só
          # quando há exatamente um candidato no pipeline canônico; com dois cards a escolha seria
          # arbitrária e criaria uma projeção que não corresponde a um fato do Engine.
          legacy_cards = projection_scope.where(operational_lead_id: nil).limit(2).to_a
          if legacy_cards.empty?
            nil
          else
            raise ProjectionIntegrityError, "ambiguous prospect projection for lead #{@lead.lead_id}" if legacy_cards.size > 1

            legacy_cards.first.tap do |card|
              card.update!(operational_lead_id: @lead.lead_id, source: 'operational_engine')
            end
          end
        end
      end
    end

    def create
      sales_lead = Sales::Lead.new(
        contact: contact,
        pipeline: pipeline,
        stage: target_stage,
        title: title,
        source: 'operational_engine',
        operational_lead_id: @lead.lead_id
      )
      sales_lead.custom_attributes = sales_lead.custom_attributes.merge(projection_attributes)
      sales_lead.save!
      sales_lead
    rescue ActiveRecord::RecordNotUnique
      # Duas tentativas podem chegar depois de a fonte já ter persistido o mesmo fato. O índice
      # técnico decide a corrida; a perdedora só relê e sincroniza a projeção vencedora.
      mapped = mapped_projection_scope.find_by!(operational_lead_id: @lead.lead_id)
      sync(mapped)
    end

    def sync(sales_lead)
      if sales_lead.sales_stage_id != target_stage.id
        Sales::Leads::MoveStageService.new(
          lead: sales_lead, stage: target_stage, user: nil, system_source: :operational_engine
        ).perform
      end

      sales_lead.update!(
        contact: contact,
        title: title,
        custom_attributes: sales_lead.custom_attributes.merge(projection_attributes)
      )
      sales_lead
    end

    def projection_attributes
      { 'engine_tags' => computed_tags, 'engine_filters' => computed_filters }
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

    def projection_scope
      Sales::Lead.where(
        account_id: @lead.conta_id,
        contact_id: @lead.upsales_contact_id,
        sales_pipeline_id: pipeline.id
      )
    end

    def mapped_projection_scope
      Sales::Lead.where(account_id: @lead.conta_id, sales_pipeline_id: pipeline.id)
    end

    # §20.1: LAVÍNIA/HUMANO são mutuamente exclusivas (o card sempre tem uma das duas); CALLBACK é
    # aditiva. NO-SHOW e a propensão FRIO/MORNO/QUENTE são do Kanban Comercial (§20.2/§20.3) --
    # Fase 9, não computadas aqui.
    def computed_tags
      tags = [@lead.modo_atendimento == 'humano' ? 'humano' : 'lavinia']
      tags << 'callback' if @lead.agendamento_status == 'callback_registrado'
      tags
    end

    # §21.1: os sete filtros do Kanban Prospect. Gravados aqui (não consultados ao vivo no
    # Supabase a cada troca de filtro) pelo mesmo motivo dos tags: Sales::* é uma projeção
    # autossuficiente, a tela não deveria precisar de uma segunda viagem de rede pro Engine só
    # pra filtrar o que já teria vindo junto no card.
    def computed_filters
      {
        'modo_entrada' => @lead.modo_entrada,
        'origem_lead' => @lead.origem_lead,
        'segmento' => @lead.segmento,
        'inbox_atual_id' => @lead.inbox_atual_id,
        'modo_atendimento' => @lead.modo_atendimento,
        'responsavel_atual_id' => @lead.responsavel_atual_id,
        'recuperacao_status' => @lead.recuperacao_status
      }
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
