require 'rails_helper'

# CP-11 (P1-VAL-08; SSOT §22, testes 28.33–28.37). event_at é gravado explicitamente: dentro da
# transação do spec o default now() do banco é constante e não diferencia os instantes.
RSpec.describe OperationalEngine::ProspectDashboardMetrics do
  let(:conta_id) { 4242 }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:setembro) { { data_inicial: '2026-09-01', data_final: '2026-09-30' } }

  def at(value)
    tz.parse(value)
  end

  def lead!(conta: conta_id, **attrs)
    OperationalEngine::Lead.create!(conta_id: conta, telefone: "+551398#{SecureRandom.random_number(10**7).to_s.rjust(7, '0')}", **attrs)
  end

  def inbound!(entrada:, **attrs)
    lead!(
      modo_entrada: 'inbound', origem_lead: 'inbound_direto', inbox_entrada_id: 10, etapa_prospect: 'em_conversa',
      entrada_operacao_em: at(entrada), etapa_entrou_em: at(entrada), **attrs
    )
  end

  def outbound!(entrada:, resposta: nil, **attrs)
    lead!(
      modo_entrada: 'outbound', origem_lead: 'busca_prospeccao', inbox_entrada_id: 20,
      etapa_prospect: resposta ? 'em_conversa' : 'contatado', entrada_operacao_em: at(entrada), primeiro_contato_em: at(entrada),
      primeira_resposta_em: resposta && at(resposta), **attrs
    )
  end

  def qualificado(em)
    { etapa_prospect: 'qualificado', qualificacao_status: 'qualificado', qualificado_em: at(em) }
  end

  def reuniao(qualificado_em:, agendado_em:)
    confirmed_meeting_attributes(at: at(agendado_em)).merge(
      qualificado_em: at(qualificado_em), conversao_em: at(agendado_em), tipo_conversao: 'agendamento'
    )
  end

  def callback_realizado(qualificado_em:, realizado_em:)
    qualificado(qualificado_em).merge(
      agendamento_status: 'callback_realizado', callback_realizado_em: at(realizado_em),
      conversao_em: at(realizado_em), tipo_conversao: 'callback'
    )
  end

  def evento!(lead, tipo, em, **metadata)
    OperationalEngine::LeadEvent.create!(lead: lead, event_type: tipo, source: 'system', event_at: at(em), metadata: metadata)
  end

  def metrics(filtros = {})
    described_class.call(conta_id: conta_id, filtros: setembro.merge(filtros))
  end

  def funil_absoluto(resultado)
    resultado[:funil][:etapas].to_h { |etapa| [etapa[:marco], etapa[:absoluto]] }
  end

  describe '28.33 coorte por entrada_operacao_em' do
    it 'lead de agosto qualificado em setembro fica fora de setembro; lead de setembro qualificado em outubro conta em setembro' do
      outbound!(entrada: '2026-08-20 10:00', resposta: '2026-08-21 10:00', **qualificado('2026-09-05 10:00'))
      setembro_lead = outbound!(entrada: '2026-09-10 10:00', resposta: '2026-09-11 10:00', **qualificado('2026-10-03 10:00'))

      resultado = metrics

      expect(resultado[:big_numbers][:leads_iniciados]).to eq(1)
      expect(resultado[:big_numbers][:qualificados]).to eq(absoluto: 1, taxa: 1.0)
      expect(resultado[:tempos_medios][:em_conversa_ate_qualificacao][:media_segundos])
        .to eq((setembro_lead.qualificado_em - setembro_lead.primeira_resposta_em).round)

      agosto = described_class.call(conta_id: conta_id, filtros: { data_inicial: '2026-08-01', data_final: '2026-08-31' })
      expect(agosto[:big_numbers][:leads_iniciados]).to eq(1)
      expect(agosto[:big_numbers][:qualificados][:absoluto]).to eq(1)
    end

    it 'usa os limites do dia em America/Sao_Paulo e isola por conta' do
      inbound!(entrada: '2026-09-30 23:30')
      inbound!(entrada: '2026-10-01 00:10')
      inbound!(entrada: '2026-08-31 23:59')
      lead!(conta: conta_id + 1, modo_entrada: 'inbound', etapa_prospect: 'em_conversa', entrada_operacao_em: at('2026-09-15 10:00'))
      lead!(etapa_prospect: 'backlog')

      expect(metrics[:big_numbers][:leads_iniciados]).to eq(1)
    end
  end

  describe '28.34 um lead por marco' do
    it 'reentradas e eventos repetidos não duplicam volumes do funil' do
      lead = outbound!(entrada: '2026-09-02 10:00', resposta: '2026-09-03 10:00', **qualificado('2026-09-04 10:00'))
      evento!(lead, 'etapa_alterada', '2026-09-03 10:00', de: 'contatado', para: 'em_conversa')
      evento!(lead, 'nova_entrada', '2026-09-10 10:00', inbox_atual_id: 30)
      evento!(lead, 'lead_reativado', '2026-09-12 10:00')
      evento!(lead, 'etapa_alterada', '2026-09-12 10:05', de: 'backlog', para: 'em_conversa')
      2.times { |i| evento!(lead, 'lead_qualificado', "2026-09-1#{i + 3} 10:00") }

      resultado = metrics

      expect(funil_absoluto(resultado)).to eq('iniciaram' => 1, 'em_conversa' => 1, 'qualificados' => 1, 'convertidos' => 0)
      expect(resultado[:tempos_medios][:entrada_ate_em_conversa]).to eq(media_segundos: 1.day.to_i, amostra: 1)
    end
  end

  describe '28.35 callback + reunião' do
    it 'conta leads únicos convertidos, nunca a soma dos dois mecanismos' do
      # §16.5: callback realizado em 04/09 converte; a reunião de 06/09 preserva agendado_em, mas
      # conversao_em/tipo_conversao ficam no primeiro marco.
      outbound!(
        entrada: '2026-09-01 10:00', resposta: '2026-09-01 11:00',
        **callback_realizado(qualificado_em: '2026-09-02 10:00', realizado_em: '2026-09-04 10:00')
          .merge(confirmed_meeting_attributes(at: at('2026-09-06 10:00')))
      )
      inbound!(entrada: '2026-09-03 10:00', **reuniao(qualificado_em: '2026-09-03 12:00', agendado_em: '2026-09-05 10:00'))
      inbound!(entrada: '2026-09-04 10:00', **callback_realizado(qualificado_em: '2026-09-04 12:00', realizado_em: '2026-09-07 10:00'))
      inbound!(entrada: '2026-09-05 10:00', **qualificado('2026-09-05 12:00'), agendamento_status: 'callback_registrado')

      resultado = metrics
      da_conta = OperationalEngine::Lead.where(conta_id: conta_id)
      soma_cega = da_conta.where.not(agendado_em: nil).count + da_conta.where.not(callback_realizado_em: nil).count

      expect(soma_cega).to eq(4)
      expect(resultado[:big_numbers][:convertidos]).to eq(absoluto: 3, taxa: 0.75)
      expect(resultado[:funil][:composicao_conversao]).to eq('agendamento' => 1, 'callback' => 2)
      expect(funil_absoluto(resultado)['convertidos']).to eq(3)
    end
  end

  describe '28.36 ciclo médio' do
    it 'lead sem endpoint não entra como zero na média; inbound pode ter tempo até conversa = zero' do
      outbound!(
        entrada: '2026-09-01 10:00', resposta: '2026-09-01 12:00',
        **reuniao(qualificado_em: '2026-09-02 10:00', agendado_em: '2026-09-03 10:00')
      )
      inbound!(entrada: '2026-09-02 10:00', **reuniao(qualificado_em: '2026-09-04 10:00', agendado_em: '2026-09-06 10:00'))
      inbound!(entrada: '2026-09-03 10:00')
      outbound!(entrada: '2026-09-04 10:00')

      tempos = metrics[:tempos_medios]

      expect(tempos[:entrada_ate_conversao]).to eq(media_segundos: 3.days.to_i, amostra: 2)
      expect(tempos[:entrada_ate_em_conversa]).to eq(media_segundos: 40.minutes.to_i, amostra: 3)
      expect(tempos[:em_conversa_ate_qualificacao]).to eq(media_segundos: (22.hours + 2.days).to_i / 2, amostra: 2)
      expect(tempos[:qualificacao_ate_conversao]).to eq(media_segundos: 1.5.days.to_i, amostra: 2)
    end

    it 'sem nenhum lead no endpoint a média fica vazia, não zero' do
      inbound!(entrada: '2026-09-03 10:00')

      expect(metrics[:tempos_medios][:entrada_ate_conversao]).to eq(media_segundos: nil, amostra: 0)
      expect(metrics[:big_numbers][:convertidos]).to eq(absoluto: 0, taxa: 0.0)
    end
  end

  describe '28.37 filtros sobre a mesma coorte' do
    before do
      inbound!(entrada: '2026-09-01 10:00', segmento: 'hotel', **qualificado('2026-09-02 10:00'))
      inbound!(entrada: '2026-09-02 10:00', segmento: 'restaurante', inbox_entrada_id: 11)
      outbound!(entrada: '2026-09-03 10:00', segmento: 'hotel')
      recuperado = outbound!(
        entrada: '2026-09-04 10:00', resposta: '2026-09-08 10:00', segmento: 'hotel',
        **reuniao(qualificado_em: '2026-09-09 10:00', agendado_em: '2026-09-10 10:00')
      )
      evento!(recuperado, 'recuperacao_iniciada', '2026-09-05 10:00')
      evento!(recuperado, 'recuperacao_respondida', '2026-09-08 10:00')
      outbound!(entrada: '2026-09-05 10:00', resposta: '2026-09-05 11:00', origem_lead: 'indicacao', segmento: 'clinica')
    end

    it 'inbound: Iniciaram = Em conversa e todo componente recalcula sobre a coorte filtrada' do
      resultado = metrics(modo: 'inbound')

      expect(funil_absoluto(resultado)).to eq('iniciaram' => 2, 'em_conversa' => 2, 'qualificados' => 1, 'convertidos' => 0)
      expect(resultado[:big_numbers][:em_conversa]).to eq(absoluto: 2, taxa: 1.0)
      expect(resultado[:tempos_medios][:entrada_ate_em_conversa]).to eq(media_segundos: 0, amostra: 2)
      expect(resultado[:tempos_medios][:entrada_ate_conversao][:amostra]).to eq(0)
      expect(resultado[:recovery]).to eq(precisaram: 0, recuperados: 0, taxa: nil, conversoes_apos_recovery: 0)
    end

    it 'outbound, origem_lead, segmento e inbox_entrada_id restringem a população de todos os indicadores' do
      outbound = metrics(modo: 'outbound')
      expect(funil_absoluto(outbound)).to eq('iniciaram' => 3, 'em_conversa' => 2, 'qualificados' => 1, 'convertidos' => 1)
      expect(outbound[:recovery]).to eq(precisaram: 1, recuperados: 1, taxa: 1.0, conversoes_apos_recovery: 1)

      expect(funil_absoluto(metrics(origem_lead: 'indicacao'))).to eq('iniciaram' => 1, 'em_conversa' => 1, 'qualificados' => 0, 'convertidos' => 0)
      expect(funil_absoluto(metrics(segmento: 'hotel', modo: 'outbound')))
        .to eq('iniciaram' => 2, 'em_conversa' => 1, 'qualificados' => 1, 'convertidos' => 1)
      expect(funil_absoluto(metrics(inbox_entrada_id: '11'))).to eq('iniciaram' => 1, 'em_conversa' => 1, 'qualificados' => 0, 'convertidos' => 0)
    end

    it 'consolidado = inbound + outbound e ignora filtros fora do §22.3' do
      consolidado = funil_absoluto(metrics(modo_atendimento: 'humano', responsavel_atual_id: 77, recuperacao_status: 'ativa'))
      inbound = funil_absoluto(metrics(modo: 'inbound'))
      outbound = funil_absoluto(metrics(modo: 'outbound'))

      expect(consolidado).to eq(inbound.merge(outbound) { |_, a, b| a + b })
      expect(consolidado['iniciaram']).to eq(5)
    end

    it 'eficiências etapa a etapa usam o marco anterior como denominador' do
      eficiencias = metrics[:funil][:etapas].to_h { |etapa| [etapa[:marco], etapa[:eficiencia]] }

      expect(eficiencias).to eq('iniciaram' => nil, 'em_conversa' => 0.8, 'qualificados' => 0.5, 'convertidos' => 0.5)
    end
  end

  describe '§22.7 recovery' do
    it 'conta precisaram, recuperados, taxa e conversões após a recuperação (sequência temporal)' do
      convertido_depois = outbound!(entrada: '2026-09-01 10:00', resposta: '2026-09-03 10:00',
                                    **reuniao(qualificado_em: '2026-09-04 10:00', agendado_em: '2026-09-05 10:00'))
      evento!(convertido_depois, 'recuperacao_iniciada', '2026-09-02 10:00')
      evento!(convertido_depois, 'recuperacao_respondida', '2026-09-03 10:00')
      convertido_antes = inbound!(entrada: '2026-09-01 10:00', **callback_realizado(qualificado_em: '2026-09-01 12:00',
                                                                                   realizado_em: '2026-09-02 10:00'))
      evento!(convertido_antes, 'recuperacao_iniciada', '2026-09-03 10:00')
      evento!(convertido_antes, 'recuperacao_respondida', '2026-09-04 10:00')
      esgotado = outbound!(entrada: '2026-09-02 10:00')
      evento!(esgotado, 'recuperacao_iniciada', '2026-09-03 10:00')
      evento!(esgotado, 'recuperacao_esgotada', '2026-09-10 10:00')
      outbound!(entrada: '2026-09-02 11:00', recuperacao_status: 'ativa')
      outbound!(entrada: '2026-09-02 12:00')

      expect(metrics[:recovery]).to eq(precisaram: 4, recuperados: 2, taxa: 0.5, conversoes_apos_recovery: 1)
    end
  end

  describe 'filtros inválidos' do
    it 'recusa modo, data e inbox fora do formato' do
      expect { metrics(modo: 'humano') }.to raise_error(described_class::InvalidFilterError, /modo/)
      expect { metrics(data_inicial: '01/09/2026') }.to raise_error(described_class::InvalidFilterError, /data_inicial/)
      expect { metrics(data_final: '2026-08-01') }.to raise_error(described_class::InvalidFilterError, /anterior/)
      expect { metrics(inbox_entrada_id: 'abc') }.to raise_error(described_class::InvalidFilterError, /inbox/)
    end
  end
end
