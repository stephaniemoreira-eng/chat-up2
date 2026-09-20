require 'rails_helper'

RSpec.describe OperationalEngine::IdempotencyRecord do
  def build_record(**attrs)
    described_class.create!({
      conta_id: 1, event_type: 'message_created', external_source: 'chatwoot',
      external_id: SecureRandom.uuid, correlation_id: SecureRandom.uuid
    }.merge(attrs))
  end

  it 'nasce como received' do
    expect(build_record.status).to eq('received')
  end

  it 'exige as chaves de dedupe' do
    expect { build_record(external_id: nil) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'exige unicidade por conta_id + event_type + external_source + external_id' do
    build_record(conta_id: 1, event_type: 'message_created', external_source: 'chatwoot', external_id: 'msg-1')

    expect do
      build_record(conta_id: 1, event_type: 'message_created', external_source: 'chatwoot', external_id: 'msg-1')
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'permite o mesmo external_id em domínios (external_source) diferentes' do
    build_record(external_source: 'chatwoot', external_id: 'shared-id')

    expect { build_record(external_source: 'google_calendar', external_id: 'shared-id') }.not_to raise_error
  end

  it 'rejeita um status fora do congelado' do
    expect { build_record(status: 'inventado') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
