require 'rails_helper'

RSpec.describe OperationalEngine::IdempotencyGuard do
  def call(external_id: 'evt-1', &block)
    described_class.call(conta_id: 1, event_type: 'message_created', external_source: 'chatwoot', external_id: external_id, &block)
  end

  it 'executa o bloco na primeira vez e marca o registro como processado' do
    result = call { 'trabalho feito' }

    expect(result).to eq('trabalho feito')
    record = OperationalEngine::IdempotencyRecord.find_by(external_id: 'evt-1')
    expect(record.status).to eq('processed')
    expect(record.processed_at).to be_present
  end

  it 'passa um correlation_id pro bloco' do
    yielded = nil
    call { |correlation_id| yielded = correlation_id }

    expect(yielded).to be_present
    expect(OperationalEngine::IdempotencyRecord.find_by(external_id: 'evt-1').correlation_id).to eq(yielded)
  end

  it 'nao executa o bloco de novo pro mesmo evento (teste 28.9)' do
    call { 'primeira vez' }

    executed_again = false
    result = call { executed_again = true }

    expect(executed_again).to be(false)
    expect(result).to be_nil
    expect(OperationalEngine::IdempotencyRecord.where(external_id: 'evt-1').count).to eq(1)
  end

  it 'processa eventos diferentes normalmente' do
    call(external_id: 'evt-1') { 'um' }
    call(external_id: 'evt-2') { 'dois' }

    expect(OperationalEngine::IdempotencyRecord.count).to eq(2)
  end

  it 'marca o registro como erro e relança a excecao quando o bloco falha' do
    expect { call { raise 'falhou' } }.to raise_error('falhou')

    record = OperationalEngine::IdempotencyRecord.find_by(external_id: 'evt-1')
    expect(record.status).to eq('error')
    expect(record.error_message).to eq('falhou')
  end
end
