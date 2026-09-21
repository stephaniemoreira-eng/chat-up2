require 'rails_helper'

RSpec.describe Sales::Prospecting::CreateLeadsFromResultsService do
  let(:account) { create(:account) }
  let(:search) { account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP') }
  let(:result) { search.results.create!(account: account, place_id: 'p1', name: 'Clinica X', phone_number: '+5513999999999') }

  describe '#perform' do
    it 'does not enqueue a scan when the account has not opted in' do
      expect do
        described_class.new(account: account, result_ids: [result.id]).perform
      end.not_to have_enqueued_job(Sales::Prospecting::ScanResultJob)
    end

    it 'enqueues a scan for the new lead when the account opted into sales_scan' do
      account.enable_features!(:sales_scan)

      expect do
        described_class.new(account: account, result_ids: [result.id]).perform
      end.to have_enqueued_job(Sales::Prospecting::ScanResultJob).with(result.id)
    end

    it 'stamps auto_contact_enabled false on the lead by default' do
      lead = described_class.new(account: account, result_ids: [result.id]).perform.first

      expect(lead.additional_attributes['auto_contact_enabled']).to be(false)
    end

    it 'stamps auto_contact_enabled true on the lead when passed through' do
      lead = described_class.new(account: account, result_ids: [result.id],
                                  auto_contact_enabled: true).perform.first

      expect(lead.additional_attributes['auto_contact_enabled']).to be(true)
    end

    it 'importa o lead pro Operational Engine em Backlog (SSOT §10.1)' do
      described_class.new(account: account, result_ids: [result.id]).perform

      engine_lead = OperationalEngine::Lead.find_by(conta_id: account.id, telefone: '+5513999999999')
      expect(engine_lead.etapa_prospect).to eq('backlog')
      expect(engine_lead.origem_lead).to eq('google_scraping')
    end

    it 'nao cria card sem o estado correspondente no Engine' do
      allow(OperationalEngine::ProspectingImporter).to receive(:call).and_raise(StandardError, 'supabase indisponivel')

      expect do
        described_class.new(account: account, result_ids: [result.id]).perform
      end.to raise_error(StandardError, 'supabase indisponivel')

      expect(Sales::Lead.count).to eq(0)
    end

    it 'cria o card apenas no pipeline canônico de Prospecção' do
      lead = described_class.new(account: account, result_ids: [result.id]).perform.first

      expect(lead.pipeline.engine_kind).to eq('prospect')
      expect(lead.stage.engine_stage_key).to eq('backlog')
    end
  end
end
