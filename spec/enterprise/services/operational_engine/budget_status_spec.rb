require 'rails_helper'

# CP-14 -- P1-VAL-13 (SSOT §6.2 orcamento_status, §14.1, §14.3, §17.1; testes 28.12 e 28.13).
# Exercitado pelo commit do turno (ApplyStructuredOutputService), que é por onde a saída estruturada
# da Lavínia chega ao Engine.
RSpec.describe OperationalEngine::BudgetStatus do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'em_conversa',
                                    orcamento_status: 'em_dimensionamento', cobertura_status: 'atendida',
                                    volume_mensal_kg: 200, retiradas_semana: 1)
  end
  let(:preco_direto) do
    'Para os 200 kg por mês que você me informou, com 1 retirada por semana, o valor do serviço é R$ 1.800,00 por mês. ' \
      'Funciona para você?'
  end

  def perform(**saida)
    OperationalEngine::ApplyStructuredOutputService.new(account: account, conversation_id: conversation.display_id, saida: saida).call
  end

  def events(type)
    OperationalEngine::LeadEvent.where(lead: lead, event_type: type)
  end

  describe '28.12 orçamento simples' do
    it 'preço direto dito num turno conversacional com dimensionamento ativo grava informado, com de/para/motivo/valor' do
      result = perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa', aguardando_resposta: true)

      expect(result[:ok]).to be(true)
      expect(lead.reload.orcamento_status).to eq('informado')
      expect(events('orcamento_informado').sole.metadata).to include(
        'de' => 'em_dimensionamento', 'para' => 'informado', 'motivo' => 'preco_direto_informado', 'valor_informado' => 'R$ 1.800,00'
      )
    end

    it 'reconhece R$ 2.500 e as grafias usuais, e não gera handoff' do
      perform(mensagem_resposta: 'Com 4 retiradas por semana, o valor é R$2.500 por mês. Funciona para você?', acao_sugerida: 'nenhuma')

      lead.reload
      expect(lead.orcamento_status).to eq('informado')
      expect(events('orcamento_informado').sole.metadata['valor_informado']).to eq('R$ 2.500,00')
      expect([lead.frente_operacional, lead.modo_atendimento, lead.etapa_comercial]).to eq(['prospeccao', 'lavinia', nil])
      expect(events('handoff_comercial')).to be_empty
    end

    it 'pedido de preço extraído no mesmo turno ativa a rota mesmo sem iniciar_orcamento antes (§14.1)' do
      lead.update!(orcamento_status: 'nao_solicitado')

      perform(dados_extraidos: { intencao_comercial: 'quer_orcamento' }, mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa')

      expect(lead.reload.orcamento_status).to eq('informado')
      expect(events('orcamento_informado').sole.metadata['de']).to eq('nao_solicitado')
    end

    it 'fora de uma rota de orçamento, um valor citado não vira orçamento informado (§14.1)' do
      lead.update!(orcamento_status: 'nao_solicitado', intencao_comercial: 'avaliando')

      perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa')

      expect(lead.reload.orcamento_status).to eq('nao_solicitado')
    end

    it 'o Engine não calcula preço: sem valor autorizado dito, dados de volume/frequência não mudam o status (§14.3)' do
      perform(dados_extraidos: { volume_mensal_kg: 300, retiradas_semana: 2 }, mensagem_resposta: 'Anotado! Deixa eu confirmar.',
              acao_sugerida: 'continuar_conversa')

      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
      expect(events('orcamento_informado')).to be_empty
    end

    it 'não confunde valores fora do §14.3 com preço direto' do
      perform(mensagem_resposta: 'Hoje vocês pagam R$ 18.000 ou R$ 1.800,50?', acao_sugerida: 'continuar_conversa')

      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
    end

    it 'turno com ação operacional não usa mensagem_resposta (a resposta pública sai da finalização)' do
      perform(mensagem_resposta: preco_direto, acao_sugerida: 'iniciar_agendamento')

      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
    end
  end

  describe '28.13 orçamento personalizado' do
    before { lead.update!(volume_mensal_kg: 600, retiradas_semana: nil) }

    it 'motivo_handoff orcamento_personalizado grava personalizado sem valor, mesmo com a ida direta para agenda (Prompt §15.4)' do
      perform(mensagem_resposta: '', acao_sugerida: 'iniciar_agendamento', motivo_handoff: 'orcamento_personalizado')

      expect(lead.reload.orcamento_status).to eq('personalizado')
      metadata = events('orcamento_personalizado').sole.metadata
      expect(metadata).to include('de' => 'em_dimensionamento', 'para' => 'personalizado', 'motivo' => 'motivo_handoff_orcamento_personalizado')
      expect(metadata).not_to have_key('valor_informado')
    end

    it 'personalizado vence um valor dito no mesmo turno' do
      perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa', motivo_handoff: 'orcamento_personalizado')

      expect(lead.reload.orcamento_status).to eq('personalizado')
      expect(events('orcamento_informado')).to be_empty
    end
  end

  describe 'máquina de estados' do
    it 'nunca rebaixa: personalizado não volta para informado nem é regravado' do
      lead.update!(orcamento_status: 'personalizado')

      perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa')
      perform(motivo_handoff: 'orcamento_personalizado', acao_sugerida: 'handoff_comercial')

      expect(lead.reload.orcamento_status).to eq('personalizado')
      expect(events('orcamento_informado')).to be_empty
      expect(events('orcamento_personalizado')).to be_empty
    end

    it 'informado repetido (ex.: retenção R$ 2.500 → R$ 1.800, §14.4) é no-op: um fato, um evento' do
      perform(mensagem_resposta: 'O valor é R$ 2.500,00 por mês. Funciona para você?', acao_sugerida: 'continuar_conversa')
      perform(mensagem_resposta: 'Consigo trabalhar R$ 1.800,00 com até 2 retiradas. Ajudaria?', acao_sugerida: 'continuar_conversa')

      expect(lead.reload.orcamento_status).to eq('informado')
      expect(events('orcamento_informado').count).to eq(1)
    end

    it 'informado avança para personalizado quando o orçamento vira avaliação personalizada' do
      lead.update!(orcamento_status: 'informado')

      perform(motivo_handoff: 'orcamento_personalizado', acao_sugerida: 'handoff_comercial')

      expect(lead.reload.orcamento_status).to eq('personalizado')
      expect(events('orcamento_personalizado').sole.metadata['de']).to eq('informado')
    end
  end

  describe 'guardas' do
    it 'modo humano: nada é aplicado' do
      lead.update!(modo_atendimento: 'humano')

      expect(perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa')[:ok]).to be(false)
      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
    end

    it 'não-contatar ou lead encerrado: o status não muda' do
      lead.update!(nao_contatar: true)
      perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa')
      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')

      lead.update!(nao_contatar: false, lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')
      perform(motivo_handoff: 'orcamento_personalizado', acao_sugerida: 'handoff_comercial')
      expect(lead.reload.orcamento_status).to eq('em_dimensionamento')
    end
  end

  it 'o Snapshot do turno seguinte expõe o status novo' do
    perform(mensagem_resposta: preco_direto, acao_sugerida: 'continuar_conversa')

    expect(OperationalEngine::SnapshotBuilder.call(lead.reload)[:estado][:orcamento_status]).to eq('informado')
  end
end
