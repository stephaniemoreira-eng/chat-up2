require 'rails_helper'

RSpec.describe OperationalEngine::BacklogCapacity do
  def ativar!(conta_id: 1, primeiro_contato_em:)
    OperationalEngine::Lead.create!(
      conta_id: conta_id, telefone: "+551399#{rand(1_000_000..9_999_999)}",
      primeiro_contato_em: primeiro_contato_em
    )
  end

  def disponivel(agora_str)
    agora = ActiveSupport::TimeZone['America/Sao_Paulo'].parse(agora_str)
    described_class.disponivel(conta_id: 1, agora: agora)
  end

  def with_test_window_override(until_at:)
    keys = [
      described_class::TEST_OVERRIDE_ENABLED_ENV,
      described_class::TEST_OVERRIDE_MODE_ENV,
      described_class::TEST_OVERRIDE_UNTIL_ENV
    ]
    previous = keys.to_h { |key| [key, ENV[key]] }

    ENV[described_class::TEST_OVERRIDE_ENABLED_ENV] = 'true'
    ENV[described_class::TEST_OVERRIDE_MODE_ENV] = described_class::TEST_OVERRIDE_FULL_DAY
    ENV[described_class::TEST_OVERRIDE_UNTIL_ENV] = until_at
    yield
  ensure
    previous&.each { |key, value| ENV[key] = value }
  end

  describe 'fora do horário operacional' do
    it 'e zero no fim de semana, mesmo dentro do horario da janela' do
      # 2026-09-19 e sabado
      expect(disponivel('2026-09-19 10:00')).to eq(0)
    end

    it 'e zero fora de qualquer janela (antes das 9h)' do
      expect(disponivel('2026-09-21 08:59')).to eq(0)
    end

    it 'e zero no intervalo entre as duas janelas (11h-14h)' do
      expect(disponivel('2026-09-21 12:30')).to eq(0)
    end

    it 'e zero depois das 16h' do
      expect(disponivel('2026-09-21 16:01')).to eq(0)
    end
  end

  describe 'dentro de uma janela, sem ativacoes ainda' do
    it 'libera o teto da janela (10), nao o teto do dia (20)' do
      expect(disponivel('2026-09-21 09:30')).to eq(10)
      expect(disponivel('2026-09-21 14:30')).to eq(10)
    end
  end

  describe 'contagem de ativacoes' do
    it 'desconta ativacoes ja feitas dentro da janela atual' do
      3.times { ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 09:15')) }
      expect(disponivel('2026-09-21 09:45')).to eq(7)
    end

    it 'nao conta ativacoes de uma janela diferente pro teto DAQUELA janela' do
      ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 09:15'))
      expect(disponivel('2026-09-21 14:30')).to eq(10)
    end

    it 'com as duas janelas do dia esgotadas (10+10=20), nao sobra nada' do
      10.times { ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 09:15')) }
      10.times { ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 14:15')) }
      expect(disponivel('2026-09-21 14:45')).to eq(0)
    end

    it 'nao conta ativacoes de outra conta' do
      10.times { ativar!(conta_id: 2, primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 09:15')) }
      expect(disponivel('2026-09-21 09:45')).to eq(10)
    end

    it 'nao compensa janela perdida: ativacoes de um dia anterior nao contam hoje' do
      ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-18 09:15'))
      expect(disponivel('2026-09-21 09:45')).to eq(10)
    end
  end

  describe 'sobrescrição temporária de homologação' do
    it 'libera o teto diário em dia útil fora da janela enquanto não expirar' do
      with_test_window_override(until_at: '2026-09-22T02:59:00Z') do
        expect(disponivel('2026-09-21 12:30')).to eq(20)
      end
    end

    it 'fecha novamente quando a expiração já passou' do
      with_test_window_override(until_at: '2026-09-21T15:29:59Z') do
        expect(disponivel('2026-09-21 12:30')).to eq(0)
      end
    end

    it 'mantém o dia não operacional bloqueado' do
      with_test_window_override(until_at: '2026-09-22T02:59:00Z') do
        expect(disponivel('2026-09-19 12:30')).to eq(0)
      end
    end

    it 'mantém o limite diário de 20 ativações' do
      20.times { ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 09:15')) }

      with_test_window_override(until_at: '2026-09-22T02:59:00Z') do
        expect(disponivel('2026-09-21 12:30')).to eq(0)
      end
    end
  end
end
