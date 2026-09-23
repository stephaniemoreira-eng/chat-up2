require 'rails_helper'

# CP-05 (P1-025-04, P1-026-02): o reconciliador pega só os pedidos pendentes vencidos.
RSpec.describe OperationalEngine::ProjectionReconcileJob do
  def lead_with_request(status:, next_attempt_at:)
    lead = OperationalEngine::Lead.create!(conta_id: 1, telefone: "+551399#{rand(1_000_000..9_999_999)}")
    OperationalEngine::ProjectionRequest.create!(lead_id: lead.lead_id, conta_id: 1, status: status, next_attempt_at: next_attempt_at)
    lead
  end

  it 'reprocessa os pedidos pendentes vencidos e ignora os futuros, sincronizados e falhos' do
    due = lead_with_request(status: 'pendente', next_attempt_at: 1.minute.ago)
    future = lead_with_request(status: 'pendente', next_attempt_at: 10.minutes.from_now)
    synced = lead_with_request(status: 'sincronizado', next_attempt_at: 1.minute.ago)
    failed = lead_with_request(status: 'falhou', next_attempt_at: nil)
    flushed = []
    allow(OperationalEngine::ProjectionReconciler).to receive(:new).and_wrap_original do |original, lead_id|
      flushed << lead_id
      original.call(lead_id)
    end

    described_class.perform_now

    expect(flushed).to eq([due.lead_id])
    expect(flushed).not_to include(future.lead_id, synced.lead_id, failed.lead_id)
    expect(OperationalEngine::ProjectionRequest.find(due.lead_id)).to be_status_sincronizado
  end
end
