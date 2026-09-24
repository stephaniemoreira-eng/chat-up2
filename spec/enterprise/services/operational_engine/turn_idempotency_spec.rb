require 'rails_helper'

# CP-03 -- P1-021-01 (SSOT §23.1).
RSpec.describe OperationalEngine::TurnIdempotency do
  let(:conta_id) { 42 }

  def run(turn_id:, operacao: 'acao:iniciar_orcamento', &)
    described_class.call(conta_id: conta_id, operacao: operacao, turn_id: turn_id, &)
  end

  it 'mesma ação do mesmo turno duas vezes -> executa uma única vez e devolve o mesmo resultado' do
    calls = 0
    first = run(turn_id: 'msg:10') do
      calls += 1
      { ok: true }
    end
    second = run(turn_id: 'msg:10') do
      calls += 1
      { ok: true }
    end

    expect(calls).to eq(1)
    expect(first).to eq(ok: true)
    expect(second).to include(ok: true, replay: true)
  end

  it 'replay tardio devolve a recusa original, mesmo se o estado mudou e hoje a ação passaria' do
    run(turn_id: 'msg:11') { { ok: false, reason: 'lead está em não-contatar' } }

    replay = run(turn_id: 'msg:11') { raise 'não deveria executar de novo' }

    expect(replay).to include(ok: false, reason: 'lead está em não-contatar', replay: true)
  end

  it 'turno novo na mesma conversa executa normalmente' do
    run(turn_id: 'msg:12') { { ok: true } }
    calls = 0

    run(turn_id: 'msg:13') do
      calls += 1
      { ok: true }
    end

    expect(calls).to eq(1)
  end

  it 'operações diferentes do mesmo turno não se bloqueiam (saída estruturada + ação)' do
    calls = 0
    run(turn_id: 'msg:14', operacao: 'saida_estruturada') do
      calls += 1
      { ok: true }
    end
    run(turn_id: 'msg:14', operacao: 'acao:iniciar_agendamento') do
      calls += 1
      { ok: true }
    end

    expect(calls).to eq(2)
  end

  it 'replay enquanto o primeiro ainda processa não executa em paralelo' do
    OperationalEngine::IdempotencyRecord.create!(conta_id: conta_id, event_type: 'acao:iniciar_orcamento',
                                                 external_source: 'lavinia_turn', external_id: 'msg:15',
                                                 correlation_id: SecureRandom.uuid)

    result = run(turn_id: 'msg:15') { raise 'não deveria executar' }

    expect(result).to eq(ok: false, reason: 'turno já em processamento')
  end

  it 'execução que estourou exceção pode ser retomada (a mutação não se completou)' do
    expect { run(turn_id: 'msg:16') { raise 'boom' } }.to raise_error('boom')

    expect(run(turn_id: 'msg:16') { { ok: true } }).to eq(ok: true)
  end

  it 'sem turn_id (chamador legado) executa sem ledger' do
    calls = 0
    2.times do
      run(turn_id: nil) do
        calls += 1
        { ok: true }
      end
    end

    expect(calls).to eq(2)
    expect(OperationalEngine::IdempotencyRecord.where(conta_id: conta_id)).to be_empty
  end
end
