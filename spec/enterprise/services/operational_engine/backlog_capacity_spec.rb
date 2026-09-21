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

      # Com os parametros aprovados (§25), teto diario = soma dos tetos de janela -- nao da pra
      # isolar "teto diario bloqueia com janela de folga" sem mudar os numeros aprovados. Este
      # teste comprova o resultado (0), nao qual dos dois tetos especificamente bateu primeiro.
      expect(disponivel('2026-09-21 14:45')).to eq(0)
    end

    it 'nao conta ativacoes de outra conta' do
      10.times { ativar!(conta_id: 2, primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-21 09:15')) }

      expect(disponivel('2026-09-21 09:45')).to eq(10)
    end

    it 'nao compensa janela perdida: ativacoes de um dia anterior nao contam hoje' do
      # 18/09 e sexta, dia util anterior a segunda 21/09 -- nao "ontem" (domingo, nem seria
      # um dia operacional possivel), so um dia diferente de "agora" pra provar o ponto.
      ativar!(primeiro_contato_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-18 09:15'))

      expect(disponivel('2026-09-21 09:45')).to eq(10)
    end
  end
end
