require 'rails_helper'

# CP-05 (P1-025-04, P1-026-02; SSOT §3.2, §23.3, §28.40, §29.3): projeção pós-commit durável,
# idempotente e observável.
RSpec.describe OperationalEngine::ProjectionReconciler do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110010', upsales_contact_id: contact.id,
                                    **comercial_opportunity_attributes(etapa_comercial: 'em_acompanhamento'))
  end

  def comercial_card
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  def request_row
    OperationalEngine::ProjectionRequest.find(lead.lead_id)
  end

  def force_request_state!(**attrs)
    OperationalEngine::ProjectionRequest.where(lead_id: lead.lead_id).update_all(attrs) # rubocop:disable Rails/SkipsModelValidations
  end

  def fail_comercial_projection!
    allow(OperationalEngine::ComercialProjectionSync).to receive(:call)
      .and_raise(OperationalEngine::ComercialProjectionSync::ProjectionIntegrityError, 'card ambíguo')
  end

  describe '.request!' do
    it 'grava o pedido pendente na mesma transação da mutação e renova a versão a cada pedido novo' do
      lead.with_lock { described_class.request!(lead, motivo: 'primeiro') }
      lead.with_lock { described_class.request!(lead, motivo: 'segundo') }

      expect(request_row).to have_attributes(status: 'pendente', version: 2, motivo: 'segundo', attempts: 0, conta_id: account.id)
    end
  end

  describe '.flush' do
    it 'sem pedido pendente é no-op' do
      expect(described_class.flush(lead)).to eq(:nada_pendente)
    end

    it 'projeta a fotografia atual e marca o pedido como sincronizado' do
      lead.with_lock { described_class.request!(lead, motivo: 'teste') }

      expect(described_class.flush(lead)).to eq(:sincronizado)
      expect(request_row).to have_attributes(status: 'sincronizado', last_error: nil)
      expect(comercial_card.stage.engine_stage_key).to eq('em_acompanhamento')
    end

    it 'falha na projeção: não sobe para quem chamou, conta a tentativa e agenda a próxima com backoff' do
      lead.with_lock { described_class.request!(lead, motivo: 'teste') }
      fail_comercial_projection!

      freeze_time do
        expect(described_class.flush(lead)).to eq(:falhou)
        expect(request_row).to have_attributes(status: 'pendente', attempts: 1, next_attempt_at: 2.minutes.from_now)
        expect(request_row.last_error).to include('ProjectionIntegrityError', 'card ambíguo')
      end
    end

    it 'um pedido mais novo no meio da tentativa não é marcado como sincronizado pela tentativa antiga' do
      lead.with_lock { described_class.request!(lead, motivo: 'antigo') }
      allow(OperationalEngine::ComercialProjectionSync).to receive(:call).and_wrap_original do |original, projected|
        lead.with_lock { described_class.request!(lead, motivo: 'novo') }
        original.call(projected)
      end

      described_class.flush(lead)

      expect(request_row).to have_attributes(status: 'pendente', version: 2, motivo: 'novo')
    end

    it 'esgotadas as tentativas, vira falhou (terminal) e emite sinal operacional' do
      lead.with_lock { described_class.request!(lead, motivo: 'teste') }
      force_request_state!(attempts: described_class::MAX_ATTEMPTS - 1)
      fail_comercial_projection!
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      described_class.flush(lead)

      expect(request_row).to have_attributes(status: 'falhou', attempts: described_class::MAX_ATTEMPTS, next_attempt_at: nil)
      expect(tracker).to have_received(:capture_exception)
    end
  end

  describe '.reprocess!' do
    it 'rearma um pedido que falhou de vez e converge a projeção' do
      lead.with_lock { described_class.request!(lead, motivo: 'teste') }
      force_request_state!(status: 'falhou', attempts: described_class::MAX_ATTEMPTS)

      expect(described_class.reprocess!(lead.lead_id)).to eq(:sincronizado)
      expect(comercial_card).to be_present
    end
  end

  # Critério de aceite do P1-025-04: falha proposital do sync após commit → retry converge o card
  # sem duplicar fato/evento.
  it 'fluxo completo: mutação confirmada + projeção falhando → job reconcilia sem duplicar eventos' do
    fail_comercial_projection!
    OperationalEngine::RegisterResultadoComercialService.call!(lead: lead, resultado: 'ganho', user_id: 9)
    events_after_commit = lead.events.count
    expect(comercial_card).to be_nil

    allow(OperationalEngine::ComercialProjectionSync).to receive(:call).and_call_original
    travel(5.minutes) { OperationalEngine::ProjectionReconcileJob.perform_now }

    expect(comercial_card.stage.engine_stage_key).to eq('ganho')
    expect(request_row).to be_status_sincronizado
    expect(lead.events.count).to eq(events_after_commit)
    expect(lead.reload.resultado_comercial).to eq('ganho')
  end
end
