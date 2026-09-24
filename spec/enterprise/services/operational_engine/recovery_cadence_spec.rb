require 'rails_helper'

# CP-13 -- P1-VAL-12 (SSOT §15.3, §15.4, §15.5, §25; testes 28.4 e 28.5): cadências, dia útil e
# janela de recovery, sempre em America/Sao_Paulo.
RSpec.describe OperationalEngine::RecoveryCadence do
  let(:zone) { Time.find_zone('America/Sao_Paulo') }
  let(:contatado) { OperationalEngine::Lead.new(etapa_prospect: 'contatado') }
  let(:em_conversa) { OperationalEngine::Lead.new(etapa_prospect: 'em_conversa') }

  def sp(*args)
    zone.local(*args)
  end

  describe '.tipo' do
    it 'Contatado = nunca respondeu; qualquer etapa depois da primeira resposta = conversava' do
      expect(described_class.tipo(contatado)).to eq('nunca_respondeu')
      %w[em_conversa qualificado agendado].each do |etapa|
        expect(described_class.tipo(OperationalEngine::Lead.new(etapa_prospect: etapa))).to eq('conversava')
      end
    end
  end

  describe 'nunca respondeu (28.4): +1, +3 e +5 dias úteis; tentativas 1-2 WhatsApp, 3 e-mail' do
    it 'conta dias úteis pulando o fim de semana e mantém o horário' do
      quinta = sp(2026, 9, 24, 10, 0) # quinta-feira

      expect(described_class.eligible_at(contatado, tentativa: 1, baseline: quinta)).to eq(sp(2026, 9, 25, 10, 0))
      expect(described_class.eligible_at(contatado, tentativa: 2, baseline: quinta)).to eq(sp(2026, 9, 29, 10, 0))
      expect(described_class.eligible_at(contatado, tentativa: 3, baseline: quinta)).to eq(sp(2026, 10, 1, 10, 0))
      expect([1, 2, 3].map { |tentativa| described_class.canal(tentativa) }).to eq(%w[whatsapp whatsapp email])
    end

    it 'um horário fora da janela carrega para a próxima janela útil' do
      sexta_noite = sp(2026, 9, 25, 20, 30)

      # +1 dia útil = segunda 20:30, fora da janela -> terça 09:00
      expect(described_class.eligible_at(contatado, tentativa: 1, baseline: sexta_noite)).to eq(sp(2026, 9, 29, 9, 0))
    end
  end

  describe 'conversava e parou (28.5): +2h, +1 dia útil, +3 dias corridos' do
    it '+2h dentro da janela é o horário mínimo exato' do
      expect(described_class.eligible_at(em_conversa, tentativa: 1, baseline: sp(2026, 9, 24, 10, 0))).to eq(sp(2026, 9, 24, 12, 0))
    end

    it '+2h que cai fora da janela carrega para a próxima janela útil (inclusive fim de semana)' do
      expect(described_class.eligible_at(em_conversa, tentativa: 1, baseline: sp(2026, 9, 24, 17, 0))).to eq(sp(2026, 9, 25, 9, 0))
      expect(described_class.eligible_at(em_conversa, tentativa: 1, baseline: sp(2026, 9, 25, 16, 30))).to eq(sp(2026, 9, 28, 9, 0))
      expect(described_class.eligible_at(em_conversa, tentativa: 1, baseline: sp(2026, 9, 24, 5, 0))).to eq(sp(2026, 9, 24, 9, 0))
    end

    it '+1 dia útil e +3 dias corridos (sábado carrega para segunda 09:00)' do
      quarta = sp(2026, 9, 23, 11, 0)

      expect(described_class.eligible_at(em_conversa, tentativa: 2, baseline: quarta)).to eq(sp(2026, 9, 24, 11, 0))
      expect(described_class.eligible_at(em_conversa, tentativa: 3, baseline: quarta)).to eq(sp(2026, 9, 28, 9, 0))
    end
  end

  describe 'parâmetros' do
    around do |example|
      keys = %w[UP_SALES_RECOVERY_CADENCE_CONVERSAVA UP_SALES_RECOVERY_WINDOW_START
                UP_SALES_RECOVERY_EXHAUST_GRACE_MINUTES UP_SALES_RECOVERY_DAILY_LIMIT]
      saved = keys.index_with { |key| ENV.fetch(key, nil) }
      example.run
    ensure
      saved.each { |key, value| ENV[key] = value }
    end

    it 'offsets vêm do ENV; valor inválido cai no padrão do SSOT' do
      ENV['UP_SALES_RECOVERY_CADENCE_CONVERSAVA'] = '1h,2bd,4d'
      expect(described_class.offsets('conversava')).to eq(%w[1h 2bd 4d])

      ENV['UP_SALES_RECOVERY_CADENCE_CONVERSAVA'] = '1h,lixo'
      expect(described_class.offsets('conversava')).to eq(%w[2h 1bd 3d])
    end

    it 'janela, folga do esgotamento e teto diário são configuráveis' do
      ENV['UP_SALES_RECOVERY_WINDOW_START'] = '10:30'
      ENV['UP_SALES_RECOVERY_EXHAUST_GRACE_MINUTES'] = '30'
      ENV['UP_SALES_RECOVERY_DAILY_LIMIT'] = '15'

      expect(OperationalEngine::RecoveryCalendar.within_window?(sp(2026, 9, 24, 10, 0))).to be(false)
      expect(described_class.eligible_at(em_conversa, tentativa: 4, baseline: sp(2026, 9, 24, 10, 0))).to eq(sp(2026, 9, 24, 10, 30))
      expect(described_class.daily_limit).to eq(15)
    end

    it 'sem teto diário por padrão' do
      ENV['UP_SALES_RECOVERY_DAILY_LIMIT'] = nil
      expect(described_class.daily_limit).to be_nil
    end
  end

  describe OperationalEngine::RecoveryCalendar do
    it 'janela = segunda a sexta, 09:00 (inclusive) a 18:00 (exclusive)' do
      expect(described_class.within_window?(sp(2026, 9, 24, 9, 0))).to be(true)
      expect(described_class.within_window?(sp(2026, 9, 24, 17, 59))).to be(true)
      expect(described_class.within_window?(sp(2026, 9, 24, 18, 0))).to be(false)
      expect(described_class.within_window?(sp(2026, 9, 26, 10, 0))).to be(false) # sábado
    end
  end
end
