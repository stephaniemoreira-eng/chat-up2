require 'rails_helper'

RSpec.describe OperationalEngine::BacklogIntake do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Lead CRM', phone_number: '+5511991234567') }
  let(:pipeline) { Sales::Pipelines::SeedProspectPipelineService.new(account: account).perform }
  let(:backlog) { pipeline.stages.find_by!(engine_stage_key: 'backlog') }
  let(:sales_lead) { create(:sales_lead, account: account, contact: contact, pipeline: pipeline, stage: backlog, title: 'Lead do CRM') }

  describe '.call' do
    it 'operacionaliza e vincula o card nativo que entra no Backlog' do
      engine_lead = described_class.call(sales_lead: sales_lead)

      expect(engine_lead).to have_attributes(
        conta_id: account.id,
        telefone: '+5511991234567',
        origem_lead: 'crm_backlog_manual',
        modo_entrada: 'outbound',
        etapa_prospect: 'backlog',
        upsales_contact_id: contact.id
      )
      expect(engine_lead.dados_origem).to include('fonte' => 'crm_backlog', 'sales_lead_id' => sales_lead.id)
      expect(sales_lead.reload.operational_lead_id).to eq(engine_lead.lead_id)
      expect(OperationalEngine::LeadEvent.where(lead: engine_lead, event_type: 'lead_criado').count).to eq(1)
    end

    it 'nao cria fila operacional sem telefone valido' do
      contact.update!(phone_number: nil)

      expect { described_class.call(sales_lead: sales_lead) }.not_to change(OperationalEngine::Lead, :count)
      expect(sales_lead.reload.operational_lead_id).to be_nil
    end

    it 'e idempotente ao receber o mesmo card novamente' do
      first = described_class.call(sales_lead: sales_lead)

      expect { described_class.call(sales_lead: sales_lead) }.not_to change(OperationalEngine::Lead, :count)
      expect(OperationalEngine::LeadEvent.where(lead: first, event_type: 'lead_criado').count).to eq(1)
    end

    it 'nao regride um lead operacional existente para Backlog' do
      existing = OperationalEngine::Lead.create!(
        conta_id: account.id, telefone: '+5511991234567', origem_lead: 'inbound_direto',
        modo_entrada: 'inbound', etapa_prospect: 'em_conversa'
      )

      result = described_class.call(sales_lead: sales_lead)

      expect(result).to eq(existing)
      expect(existing.reload).to have_attributes(etapa_prospect: 'em_conversa', origem_lead: 'inbound_direto', upsales_contact_id: contact.id)
      expect(sales_lead.reload.operational_lead_id).to eq(existing.lead_id)
      expect(sales_lead.stage.engine_stage_key).to eq('em_conversa')
    end

    it 'ignora cards fora do Backlog do funil Prospecção' do
      other_stage = pipeline.stages.find_by!(engine_stage_key: 'contatado')
      sales_lead.update!(stage: other_stage)

      expect { described_class.call(sales_lead: sales_lead) }.not_to change(OperationalEngine::Lead, :count)
    end
  end
end
