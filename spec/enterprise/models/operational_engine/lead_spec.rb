require 'rails_helper'

RSpec.describe OperationalEngine::Lead do
  def build_lead(**attrs)
    described_class.create!({ conta_id: 1, telefone: "+551399#{rand(1_000_000..9_999_999)}" }.merge(attrs))
  end

  describe 'conta_id' do
    it 'exige presenca' do
      expect { build_lead(conta_id: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'telefone' do
    it 'normaliza um numero informado em formato solto' do
      lead = build_lead(telefone: '+55 (13) 99123-4567')

      expect(lead.telefone).to eq('+5513991234567')
    end

    it 'exige presenca' do
      expect { build_lead(telefone: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'exige unicidade por conta' do
      build_lead(conta_id: 1, telefone: '+5513991234567')

      expect { build_lead(conta_id: 1, telefone: '+5513991234567') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'permite o mesmo numero em contas (clientes Up Sales) diferentes' do
      build_lead(conta_id: 1, telefone: '+5513991234567')

      expect { build_lead(conta_id: 2, telefone: '+5513991234567') }.not_to raise_error
    end
  end

  describe 'defaults' do
    it 'nasce em backlog, ativo, em_qualificacao, na frente de prospeccao' do
      lead = build_lead

      expect(lead.etapa_prospect).to eq('backlog')
      expect(lead.lead_status).to eq('ativo')
      expect(lead.qualificacao_status).to eq('em_qualificacao')
      expect(lead.frente_operacional).to eq('prospeccao')
    end
  end

  describe 'enums' do
    it 'rejeita um valor fora do congelado no SSOT §6.2' do
      # validate: true troca o ArgumentError imediato do enum por uma validação Rails normal.
      expect { build_lead(etapa_prospect: 'inventado') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'aceita etapa_comercial nula antes da oportunidade' do
      lead = build_lead(etapa_comercial: nil)

      expect(lead.etapa_comercial).to be_nil
    end
  end

  describe 'campos write-once (SSOT §6.3)' do
    it 'nao deixa reescrever origem_lead depois de definido' do
      lead = build_lead(origem_lead: 'scan')

      expect { lead.update!(origem_lead: 'manual') }.to raise_error(ActiveRecord::StatementInvalid, /write-once/)
    end

    it 'nao deixa reescrever inbox_entrada_id depois de definido' do
      lead = build_lead(inbox_entrada_id: 5)

      expect { lead.update!(inbox_entrada_id: 9) }.to raise_error(ActiveRecord::StatementInvalid, /write-once/)
    end

    it 'nao deixa reescrever entrada_operacao_em depois de definido' do
      lead = build_lead(entrada_operacao_em: 1.day.ago)

      expect { lead.update!(entrada_operacao_em: Time.current) }.to raise_error(ActiveRecord::StatementInvalid, /write-once/)
    end

    # Split into two examples on purpose: a raised trigger error leaves the transaction aborted,
    # so a second update! in the same example would fail on that instead of on write-once.
    it 'nao deixa reescrever conversao_em depois do primeiro marco' do
      lead = build_lead(conversao_em: 1.day.ago, tipo_conversao: 'agendamento')

      expect { lead.update!(conversao_em: Time.current) }.to raise_error(ActiveRecord::StatementInvalid, /write-once/)
    end

    it 'nao deixa reescrever tipo_conversao depois do primeiro marco de conversao' do
      lead = build_lead(conversao_em: 1.day.ago, tipo_conversao: 'agendamento')

      expect { lead.update!(tipo_conversao: 'callback') }.to raise_error(ActiveRecord::StatementInvalid, /locked once conversao_em/)
    end

    it 'permite preencher esses campos pela primeira vez' do
      lead = build_lead

      expect { lead.update!(origem_lead: 'scan', inbox_entrada_id: 5) }.not_to raise_error
    end
  end
end
