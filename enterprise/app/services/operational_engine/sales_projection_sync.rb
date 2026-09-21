# §5.2/§5.3: Sales::Lead é projeção visual, nunca fonte de verdade -- esta é a ÚNICA direção
# permitida (Supabase → Sales::*). Nunca chame isto a partir de um controller/tela do UpSales.
#
# Escopo da Fase 2, de propósito estreito: garante que existe um Sales::Lead pra aparecer no
# Kanban, com `title` refletido. Mapear `etapa_prospect`/`frente_operacional` pra pipeline/stage
# específicos é decisão de negócio da Fase 5/9 (§32) -- os stages hoje seedados por
# Sales::Pipelines::SeedDefaultService nem correspondem aos do SSOT ainda. Até lá, todo lead
# novo entra no pipeline default, na primeira stage, e fica lá.
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

      sales_lead = existing || build
      sales_lead.title = title
      sales_lead.save!
      sales_lead
    end

    private

    def existing
      Sales::Lead.find_by(account_id: @lead.conta_id, contact_id: @lead.upsales_contact_id)
    end

    def build
      pipeline = Sales::Pipelines::SeedDefaultService.new(account: account).perform
      Sales::Lead.new(contact: contact, pipeline: pipeline, stage: pipeline.stages.ordered.first)
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
