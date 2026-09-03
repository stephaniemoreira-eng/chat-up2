require 'rails_helper'

RSpec.describe Sales::Prospecting::ScanService do
  let(:account) { create(:account) }
  let(:search) { account.sales_prospecting_searches.create!(business_type: 'clinica estetica', city: 'Santos', state: 'SP') }
  let(:result) do
    search.results.create!(
      account: account,
      place_id: 'p1',
      name: 'Clinica X',
      website: 'https://clinicax.com.br',
      rating: 3.0,
      user_ratings_total: 8
    )
  end

  let(:place_details) do
    { business_status: 'OPERATIONAL', primary_type: 'beauty_salon', has_opening_hours: false,
      has_website: true, has_phone: true, rating: 4.5, user_ratings_total: 25 }
  end
  let(:pagespeed) { { performance_score: 80, seo_score: 90, best_practices_score: 70 } }
  let(:scanner_response) do
    {
      'site' => { 'title' => 'Clinica Estetica Bela Pele', 'description' => 'Tratamentos faciais e corporais',
                  'has_whatsapp' => true, 'has_cta' => true, 'has_ecommerce' => false,
                  'instagram_url' => 'https://www.instagram.com/clinicax' },
      'instagram' => { 'followers' => 1500, 'posts' => 45, 'bio' => 'Clinica de estetica facial e corporal.' }
    }
  end

  before do
    allow(Sales::Prospecting::PlaceDetailsService).to receive(:call).and_return(place_details)
    allow(Sales::Prospecting::PageSpeedService).to receive(:call).and_return(pagespeed)
    allow(Sales::Prospecting::ScannerClientService).to receive(:call).and_return(scanner_response)
    allow(Sales::Prospecting::BioClassifierService).to receive(:call).and_return(clareza: true, profissionalismo: true)
  end

  describe '.call' do
    it 'computes each pillar deterministically and persists the breakdown' do
      described_class.call(result)
      result.reload

      expect(result.scan_status).to eq('concluido')
      expect(result.scan_pilares).to eq('website' => 25, 'maps' => 26, 'instagram' => 21, 'icp' => 11)
      expect(result.scan_score).to eq(83)
      expect(result.scan_faixa).to eq('revisao_prioritaria')
    end

    it 'never approves or releases sending, regardless of score' do
      described_class.call(result)
      result.reload

      expect(result.scan_aprovado).to be(false)
      expect(result.scan_liberado_envio).to be(false)
    end

    it 'uses Place Details data over the rating captured at search time' do
      described_class.call(result)
      result.reload

      expect(result.scan_evidencias.dig('indicadores', 'maps', 'rating')).to eq(4.5)
    end

    it 'falls back to the search-captured rating when Place Details is unavailable' do
      allow(Sales::Prospecting::PlaceDetailsService).to receive(:call).and_return(nil)

      described_class.call(result)
      result.reload

      # rating 3.0/5 * 10 = 6, avaliacoes 8 (<=10) => (5*0.4).round = 2 -> maps = 8
      expect(result.scan_pilares['maps']).to eq(8)
      expect(result.scan_evidencias['dados_nao_encontrados']).to include('place_details')
      expect(result.scan_evidencias['alertas']).to include(a_string_matching(/Google Maps/))
    end

    it 'zeroes the website pillar and flags it when there is no website' do
      result.update!(website: nil)

      described_class.call(result)
      result.reload

      expect(result.scan_pilares['website']).to eq(0)
      expect(result.scan_evidencias['dados_nao_encontrados']).to include('website')
    end

    it 'skips the bio bonus and flags it when the bio classifier fails' do
      allow(Sales::Prospecting::BioClassifierService).to receive(:call).and_return(nil)

      described_class.call(result)
      result.reload

      # instagram sem os 10 pontos da bio: 21 - 10 = 11
      expect(result.scan_pilares['instagram']).to eq(11)
      expect(result.scan_evidencias['dados_nao_encontrados']).to include('bio_classificacao')
    end

    it 'marks the result as erro instead of raising when a data source blows up' do
      allow(Sales::Prospecting::PageSpeedService).to receive(:call).and_raise(StandardError, 'boom')

      expect { described_class.call(result) }.not_to raise_error
      expect(result.reload.scan_status).to eq('erro')
    end
  end

  describe 'Instagram retry on likely IP block' do
    let(:blocked_scanner_response) do
      {
        'site' => { 'title' => 'Clinica Estetica Bela Pele', 'description' => 'Tratamentos faciais',
                    'has_whatsapp' => true, 'has_cta' => true, 'has_ecommerce' => false,
                    'instagram_url' => 'https://www.instagram.com/clinicax' },
        'instagram' => { 'followers' => 0, 'posts' => 0, 'bio' => '' }
      }
    end

    it 'schedules a retry when the profile was found but came back completely empty' do
      allow(Sales::Prospecting::ScannerClientService).to receive(:call).and_return(blocked_scanner_response)

      expect do
        described_class.call(result)
      end.to have_enqueued_job(Sales::Prospecting::ScanResultJob).with(result.id)

      evidencias = result.reload.scan_evidencias
      expect(evidencias['instagram_retry_count']).to eq(1)
      expect(evidencias['alertas']).to include(a_string_matching(/bloqueio temporario/))
    end

    it 'does not schedule a retry when Instagram data came back normally' do
      expect do
        described_class.call(result)
      end.not_to have_enqueued_job(Sales::Prospecting::ScanResultJob)
    end

    it 'does not schedule a retry when there is no Instagram profile at all' do
      no_profile_response = blocked_scanner_response.deep_merge('site' => { 'instagram_url' => '' })
      allow(Sales::Prospecting::ScannerClientService).to receive(:call).and_return(no_profile_response)

      expect do
        described_class.call(result)
      end.not_to have_enqueued_job(Sales::Prospecting::ScanResultJob)
    end

    it 'does not retry a second time once the limit is reached' do
      result.update!(scan_evidencias: { 'instagram_retry_count' => 1 })
      allow(Sales::Prospecting::ScannerClientService).to receive(:call).and_return(blocked_scanner_response)

      expect do
        described_class.call(result)
      end.not_to have_enqueued_job(Sales::Prospecting::ScanResultJob)
      expect(result.reload.scan_evidencias['instagram_retry_count']).to eq(1)
    end
  end
end
