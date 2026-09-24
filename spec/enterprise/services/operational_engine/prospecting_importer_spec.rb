require 'rails_helper'

RSpec.describe OperationalEngine::ProspectingImporter do
  let(:account) { create(:account) }
  let(:search) do
    account.sales_prospecting_searches.create!(business_type: 'lava rapido', neighborhood: 'Gonzaga',
                                               city: 'Santos', state: 'SP')
  end
  let(:result) do
    search.results.create!(account: account, place_id: 'place-1', name: 'Lava Rapido do Ze',
                           phone_number: '+5513999990001', address: 'Av. Ana Costa, 100',
                           website: 'https://lavarapidodoze.com.br', rating: 4.5, user_ratings_total: 120)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5513999990001') }

  def import
    described_class.call(result: result, contact: contact)
  end

  it 'nao cria lead no Engine quando o contato nao tem telefone' do
    contact.update!(phone_number: nil)

    expect { import }.not_to change(OperationalEngine::Lead, :count)
  end

  describe 'lead novo (§10.1)' do
    it 'nasce em backlog, outbound, google_scraping, na frente de prospeccao' do
      lead = import

      expect(lead.etapa_prospect).to eq('backlog')
      expect(lead.modo_entrada).to eq('outbound')
      expect(lead.origem_lead).to eq('google_scraping')
      expect(lead.frente_operacional).to eq('prospeccao')
      expect(lead.lead_status).to eq('ativo')
    end

    it 'nao preenche entrada_operacao_em -- Backlog e estoque, nao operacao iniciada (teste 28.1)' do
      lead = import

      expect(lead.entrada_operacao_em).to be_nil
      expect(lead.primeiro_contato_em).to be_nil
    end

    it 'preenche etapa_entrou_em, que e por onde o FIFO do Backlog ordena (§10.3)' do
      lead = import

      expect(lead.etapa_entrou_em).to be_present
    end

    it 'guarda empresa, segmento, regiao operacional e a referencia do contato' do
      lead = import

      expect(lead.empresa).to eq('Lava Rapido do Ze')
      expect(lead.segmento).to eq('lava rapido')
      expect(lead.regiao).to eq('Gonzaga - Santos/SP')
      expect(lead.upsales_contact_id).to eq(contact.id)
    end

    it 'guarda os dados especificos da aquisicao em dados_origem (§5.4)' do
      lead = import.reload

      expect(lead.dados_origem).to include(
        'fonte' => 'busca_prospeccao',
        'place_id' => 'place-1',
        'prospecting_search_id' => search.id,
        'prospecting_result_id' => result.id
      )
    end

    it 'registra lead_criado com source import' do
      lead = import

      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'lead_criado')
      expect(event.source).to eq('import')
    end
  end

  describe 'lead que ja existe pelo telefone (§5.4, teste 28.8)' do
    let!(:existente) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513999990001',
                                      origem_lead: 'inbound_direto', modo_entrada: 'inbound',
                                      etapa_prospect: 'em_conversa')
    end

    it 'nao duplica o lead' do
      expect { import }.not_to change(OperationalEngine::Lead, :count)
    end

    it 'nao sobrescreve a origem original nem devolve o lead pro Backlog' do
      import

      expect(existente.reload.origem_lead).to eq('inbound_direto')
      expect(existente.reload.etapa_prospect).to eq('em_conversa')
    end

    it 'registra a nova ocorrencia em vez de lead_criado' do
      lead = import

      types = OperationalEngine::LeadEvent.where(lead: lead).pluck(:event_type)
      expect(types).to contain_exactly('nova_entrada')
    end

    it 'preenche a referencia do contato quando ela ainda nao existia' do
      import

      expect(existente.reload.upsales_contact_id).to eq(contact.id)
    end
  end

  # CP-09 -- P2-VAL-06 (SSOT §19.1, teste 28.24).
  describe 'lead que ja e cliente atual achado na busca' do
    let!(:cliente) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513999990001', origem_lead: 'csv', modo_entrada: 'outbound',
                                      relacao_atual: 'cliente_atual', etapa_prospect: 'backlog', etapa_entrou_em: 1.day.ago)
    end

    def encerramentos
      OperationalEngine::LeadEvent.where(lead: cliente, event_type: 'lead_encerrado')
    end

    it 'encerra o ciclo Prospect como cliente_atual em vez de deixar ativo em Backlog' do
      import

      cliente.reload
      expect(cliente.lead_status).to eq('encerrado')
      expect(cliente.motivo_encerramento).to eq('cliente_atual')
      expect(cliente.etapa_prospect).to eq('backlog')
      expect(cliente.relacao_atual).to eq('cliente_atual')
    end

    it 'registra lead_encerrado com de/para/motivo (§7.3) alem da nova_entrada' do
      import

      expect(encerramentos.count).to eq(1)
      expect(encerramentos.first.metadata).to include('de' => 'ativo', 'para' => 'encerrado', 'motivo' => 'cliente_atual',
                                                      'motivo_encerramento' => 'cliente_atual')
      expect(encerramentos.first.source).to eq('import')
      expect(OperationalEngine::LeadEvent.where(lead: cliente, event_type: 'nova_entrada').count).to eq(1)
    end

    it 'nao prospecta: o lead nao volta para a fila do Backlog' do
      import

      expect(OperationalEngine::BacklogSelector.candidatos(conta_id: account.id)).not_to include(cliente)
    end

    it 'tambem encerra um cliente atual em Contatado' do
      cliente.update!(etapa_prospect: 'contatado')

      import

      expect(cliente.reload.motivo_encerramento).to eq('cliente_atual')
    end

    it 'reimportar (outro resultado da busca) nao encerra de novo nem duplica o evento' do
      import
      outro = search.results.create!(account: account, place_id: 'place-2', name: 'Lava Rapido do Ze', phone_number: '+5513999990001')

      described_class.call(result: outro, contact: contact)

      expect(encerramentos.count).to eq(1)
    end

    it 'nao encerra um cliente atual em conversa (interacao real, §19.1 permite responder)' do
      cliente.update!(etapa_prospect: 'em_conversa')

      import

      expect(cliente.reload.lead_status).to eq('ativo')
      expect(encerramentos).to be_empty
    end

    it 'nao encerra um cliente atual com oportunidade na frente Comercial' do
      cliente.update!(comercial_opportunity_attributes)

      import

      expect(cliente.reload.lead_status).to eq('ativo')
    end

    it 'nao troca o motivo de um lead ja encerrado por outro motivo' do
      cliente.update!(lead_status: 'encerrado', motivo_encerramento: 'nao_contatar', nao_contatar: true)

      import

      expect(cliente.reload.motivo_encerramento).to eq('nao_contatar')
      expect(encerramentos).to be_empty
    end

    it 'prospect comum achado de novo continua ativo' do
      cliente.update!(relacao_atual: 'prospect')

      import

      expect(cliente.reload.lead_status).to eq('ativo')
    end
  end

  it 'reprocessar o mesmo resultado nao registra o lead como achado de novo (teste 28.9)' do
    import

    expect { import }.not_to change(OperationalEngine::LeadEvent, :count)
  end
end
