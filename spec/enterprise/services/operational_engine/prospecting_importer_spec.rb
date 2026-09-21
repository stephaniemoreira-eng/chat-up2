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

  it 'reprocessar o mesmo resultado nao registra o lead como achado de novo (teste 28.9)' do
    import

    expect { import }.not_to change(OperationalEngine::LeadEvent, :count)
  end
end
