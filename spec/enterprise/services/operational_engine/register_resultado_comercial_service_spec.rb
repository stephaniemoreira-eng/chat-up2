require 'rails_helper'

RSpec.describe OperationalEngine::RegisterResultadoComercialService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  # CP-05 (P2-025-01): oportunidade Comercial completa (handoff real) em Em acompanhamento -- o único
  # ponto de onde o §8.4 permite resolver.
  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id,
      **comercial_opportunity_attributes(etapa_comercial: 'em_acompanhamento')
    }.merge(overrides))
  end

  # O lead tem card nos dois pipelines (Prospect e Comercial) -- escopar pelo Comercial.
  def comercial_sales_lead(lead)
    pipeline = Sales::Pipelines::SeedComercialPipelineService.new(account: account).perform
    Sales::Lead.find_by(operational_lead_id: lead.lead_id, sales_pipeline_id: pipeline.id)
  end

  describe 'ganho (§17.4, §19.1, §28.30)' do
    it 'grava resultado, etapa, ganho_em, cliente atual, lead encerrado e motivo_encerramento cliente_atual' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)
      lead.reload

      expect(lead.resultado_comercial).to eq('ganho')
      expect(lead.etapa_comercial).to eq('ganho')
      expect(lead.ganho_em).to be_present
      expect(lead.relacao_atual).to eq('cliente_atual')
      expect(lead.lead_status).to eq('encerrado')
      expect(lead.motivo_encerramento).to eq('cliente_atual')
    end

    it 'preserva a conversão Prospect anterior (conversao_em/tipo_conversao)' do
      convertido_em = 5.days.ago.change(usec: 0)
      lead = build_lead(conversao_em: convertido_em, tipo_conversao: 'callback', callback_realizado_em: convertido_em,
                        agendamento_status: 'callback_realizado')

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)

      expect(lead.reload.conversao_em).to eq(convertido_em)
      expect(lead.tipo_conversao).to eq('callback')
    end

    it 'move o card pra coluna Ganho' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)

      sales_lead = comercial_sales_lead(lead)
      expect(sales_lead.stage.engine_stage_key).to eq('ganho')
      expect(sales_lead).to be_won
    end

    # CP-05 (P2-025-02, §7.4): resultado, passagem para cliente atual e encerramento reconstruíveis.
    it 'registra resultado_ganho, relacao_atualizada e lead_encerrado com de/para/motivo' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)

      expect(lead.events.find_by(event_type: 'resultado_ganho').metadata).to include('de' => 'em_acompanhamento', 'para' => 'ganho')
      expect(lead.events.find_by(event_type: 'relacao_atualizada').metadata)
        .to include('de' => nil, 'para' => 'cliente_atual', 'motivo' => 'resultado_ganho')
      expect(lead.events.find_by(event_type: 'lead_encerrado').metadata)
        .to include('de' => 'ativo', 'para' => 'encerrado', 'motivo' => 'resultado_ganho', 'motivo_encerramento' => 'cliente_atual')
    end
  end

  describe 'perdido (§17.4, §28.31)' do
    it 'grava resultado_comercial, etapa_comercial e motivo_perda opcional' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'perdido', user_id: 9, motivo_perda: 'escolheu concorrente')
      lead.reload

      expect(lead.resultado_comercial).to eq('perdido')
      expect(lead.etapa_comercial).to eq('perdido')
      expect(lead.motivo_perda).to eq('escolheu concorrente')
      expect(lead.lead_status).to eq('encerrado')
      expect(lead.ganho_em).to be_nil
      expect(lead.relacao_atual).to be_nil
    end

    it 'permite perdido sem motivo_perda (opcional)' do
      lead = build_lead

      expect { described_class.call!(lead: lead, resultado: 'perdido', user_id: 9) }.not_to raise_error
      expect(lead.reload.motivo_perda).to be_nil
    end

    it 'preserva a conversão Prospect anterior' do
      convertido_em = 3.days.ago.change(usec: 0)
      lead = build_lead(conversao_em: convertido_em, tipo_conversao: 'agendamento', **confirmed_meeting_attributes(at: convertido_em))

      described_class.call!(lead: lead, resultado: 'perdido', user_id: 9)

      expect(lead.reload.conversao_em).to eq(convertido_em)
      expect(lead.tipo_conversao).to eq('agendamento')
    end

    it 'registra resultado_perdido e lead_encerrado, sem relacao_atualizada' do
      lead = build_lead

      described_class.call!(lead: lead, resultado: 'perdido', user_id: 9)

      expect(lead.events.where(event_type: %w[resultado_perdido lead_encerrado]).count).to eq(2)
      expect(lead.events.where(event_type: 'relacao_atualizada')).to be_empty
    end
  end

  it 'levanta AlreadyResolvedError quando a oportunidade ja foi resolvida, sem duplicar eventos' do
    lead = build_lead
    described_class.call!(lead: lead, resultado: 'ganho', user_id: 9)

    expect { described_class.call!(lead: lead, resultado: 'perdido', user_id: 9) }
      .to raise_error(described_class::AlreadyResolvedError)
    expect(lead.reload.resultado_comercial).to eq('ganho')
    expect(lead.events.where(event_type: %w[resultado_ganho resultado_perdido lead_encerrado]).count).to eq(2)
  end

  it 'levanta InvalidResultadoError pra um valor fora de ganho/perdido' do
    lead = build_lead

    expect { described_class.call!(lead: lead, resultado: 'em_aberto', user_id: 9) }
      .to raise_error(described_class::InvalidResultadoError)
  end

  # CP-05 (P1-025-02, §8.4): guarda de backend, independente do botão.
  describe 'guardas de contexto Comercial' do
    it 'recusa resolver direto de Oportunidade (sequência §8.4)' do
      lead = build_lead(etapa_comercial: 'oportunidade')

      expect { described_class.call!(lead: lead, resultado: 'ganho', user_id: 9) }
        .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
      expect(lead.reload.resultado_comercial).to eq('em_aberto')
      expect(lead.relacao_atual).to be_nil
      expect(lead.events).to be_empty
    end

    it 'recusa um lead sem oportunidade Comercial (Prospect puro)' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110000', upsales_contact_id: contact.id,
                                             etapa_prospect: 'em_conversa')

      expect { described_class.call!(lead: lead, resultado: 'ganho', user_id: 9) }
        .to raise_error(OperationalEngine::ComercialActionGuard::InvalidContextError)
      expect(lead.reload.lead_status).to eq('ativo')
      expect(lead.etapa_comercial).to be_nil
    end
  end

  # CP-05 (P1-025-04): falha da projeção depois do commit não desfaz nem esconde o fato.
  it 'com a projeção falhando, o resultado fica persistido e a projeção pendente para o reconciliador' do
    lead = build_lead
    allow(OperationalEngine::ComercialProjectionSync).to receive(:call)
      .and_raise(OperationalEngine::ComercialProjectionSync::ProjectionIntegrityError, 'ambíguo')

    expect { described_class.call!(lead: lead, resultado: 'ganho', user_id: 9) }.not_to raise_error

    expect(lead.reload.resultado_comercial).to eq('ganho')
    request = OperationalEngine::ProjectionRequest.find(lead.lead_id)
    expect(request).to be_status_pendente
    expect(request.attempts).to eq(1)
    expect(request.last_error).to include('ambíguo')
  end
end
