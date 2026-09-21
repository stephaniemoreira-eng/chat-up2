# §5.2/§5.3: mesma regra de OperationalEngine::SalesProjectionSync -- projeção visual, nunca
# fonte de verdade, ÚNICA direção permitida (Supabase → Sales::*).
#
# Fase 9 (§8.4, §20.2, §20.3, §21.3): pipeline "Oportunidades", dedicado ao funil Comercial,
# separado do pipeline "Prospecção" que SalesProjectionSync mantém -- são dois cards distintos
# pro mesmo contato quando ambos existem (um por pipeline), nunca o mesmo Sales::Lead.
#
# Diferença central pro Prospect: aqui a existência do card é CONDICIONAL. "Antes de existir
# oportunidade, etapa_comercial = null" (§8.4) -- sem oportunidade não há card nenhum a
# sincronizar, e não criamos um só pra já deixar pronto (isso inventaria um "Oportunidade"
# vazio que nenhum evento de negócio gerou).
#
# Não é chamado a partir de nenhum caminho que já existe hoje: nada em chat-up2 ainda escreve
# etapa_comercial (isso nasce de handoff/callback/qualificação -- Fase 4/8, ainda não
# construídas). Já vai encaixado nos mesmos pontos de disparo do SalesProjectionSync (inbound,
# Assumir/Devolver) pelo mesmo motivo de sempre: sem custo chamar num lead que não tem
# oportunidade ainda (só um early return), e quando o campo passar a ser escrito de verdade a
# sincronização já funciona sem precisar lembrar de encontrar todo ponto de disparo depois.
module OperationalEngine
  class ComercialProjectionSync
    class ProjectionIntegrityError < StandardError; end
    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    def call
      return unless contact
      return unless @lead.etapa_comercial.present?

      existing ? sync(existing) : create
    end

    private

    def existing
      @existing ||= begin
        mapped = mapped_projection_scope.find_by(operational_lead_id: @lead.lead_id)
        if mapped
          mapped
        else
          legacy_cards = legacy_projection_scope.limit(2).to_a
          if legacy_cards.empty?
            nil
          else
            raise ProjectionIntegrityError, "ambiguous commercial projection for lead #{@lead.lead_id}" if legacy_cards.size > 1

            legacy_cards.first.tap do |card|
              card.update!(operational_lead_id: @lead.lead_id, source: 'operational_engine')
            end
          end
        end
      end
    end

    # status/closed_at setados a mão (não só stage:) porque um lead pode chegar ao Engine já
    # 'ganho'/'perdido' na primeíssima sincronização -- não existe #perform do MoveStageService
    # pra chamar aqui (não há "mover" um card que ainda não tinha stage nenhuma), mas o card
    # precisa nascer com o mesmo status que #perform derivaria, não com o default 'open' da
    # coluna.
    def create
      sales_lead = Sales::Lead.new(
        contact: contact, pipeline: pipeline, stage: target_stage, title: title,
        source: 'operational_engine', operational_lead_id: @lead.lead_id,
        status: Sales::Leads::MoveStageService.status_for(target_stage),
        closed_at: target_stage.open? ? nil : Time.current
      )
      sales_lead.custom_attributes = sales_lead.custom_attributes.merge('engine_tags' => computed_tags)
      sales_lead.save!
      sales_lead
    rescue ActiveRecord::RecordNotUnique
      sync(mapped_projection_scope.find_by!(operational_lead_id: @lead.lead_id))
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
        custom_attributes: sales_lead.custom_attributes.merge('engine_tags' => computed_tags)
      )
      sales_lead
    end

    # bang de propósito, mesmo raciocínio de SalesProjectionSync#target_stage: as quatro stages
    # nascem juntas em SeedComercialPipelineService, uma ausência aqui é uma stage apagada por
    # engano, não um estado esperado.
    def target_stage
      @target_stage ||= pipeline.stages.find_by!(engine_stage_key: @lead.etapa_comercial)
    end

    def pipeline
      @pipeline ||= Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    end

    def mapped_projection_scope
      Sales::Lead.where(account_id: @lead.conta_id, sales_pipeline_id: pipeline.id)
    end

    def legacy_projection_scope
      mapped_projection_scope.where(contact_id: @lead.upsales_contact_id, operational_lead_id: nil)
    end

    # §20.2/§20.3: propensão é classificação manual (nao_classificado não vira tag -- é "ainda
    # sem classificação", não um valor pra mostrar). CALLBACK usa a mesma condição do Prospect
    # (§16.2, agendamento_status compartilhado entre os dois funis). NO-SHOW é a exceção
    # transversal: aparece sem mudar a etapa nem encerrar a oportunidade.
    def computed_tags
      tags = []
      tags << @lead.propensao_fechamento if %w[frio morno quente].include?(@lead.propensao_fechamento)
      tags << 'callback' if @lead.agendamento_status == 'callback_registrado'
      tags << 'no_show' if @lead.no_show_em.present?
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
