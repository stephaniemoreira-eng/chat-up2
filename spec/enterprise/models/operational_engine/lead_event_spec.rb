require 'rails_helper'

RSpec.describe OperationalEngine::LeadEvent do
  let(:lead) { OperationalEngine::Lead.create!(telefone: "+551399#{rand(1_000_000..9_999_999)}") }

  def build_event(**attrs)
    described_class.create!({ lead: lead, event_type: 'lead_criado', source: 'system' }.merge(attrs))
  end

  it 'exige event_type' do
    expect { build_event(event_type: nil) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejeita uma origem fora do congelado no SSOT §7.1' do
    # validate: true troca o ArgumentError imediato do enum por uma validação Rails normal.
    expect { build_event(source: 'inventado') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  describe 'append-only (SSOT §7.2)' do
    it 'e readonly para o Rails assim que persistido' do
      event = build_event

      expect { event.update!(event_type: 'lead_enriquecido') }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    # Split into two examples on purpose: a raised error leaves a Postgres transaction aborted
    # until rollback, so a second raw statement in the same example would fail on that instead
    # of on the trigger it is meant to prove.
    it 'UPDATE falha no banco mesmo contornando o Rails (garantia é do Postgres, nao só do model)' do
      event = build_event
      conn = described_class.connection

      expect do
        conn.execute("UPDATE lead_events SET event_type = 'x' WHERE event_id = #{conn.quote(event.event_id)}")
      end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    end

    it 'DELETE falha no banco mesmo contornando o Rails' do
      event = build_event
      conn = described_class.connection

      expect do
        conn.execute("DELETE FROM lead_events WHERE event_id = #{conn.quote(event.event_id)}")
      end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    end
  end
end
