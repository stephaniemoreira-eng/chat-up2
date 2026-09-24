require 'rails_helper'

# CP-16B -- P2-VAL-20 (decisão da Stéphanie em 24/09/2026): depois da devolução, a Lavínia relê a
# conversa num turno silencioso e o Engine grava o ultimo_ponto novo, se houver. A devolução já está
# gravada quando isso roda -- nada aqui a desfaz.
RSpec.describe OperationalEngine::DevolucaoResync do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:user) { create(:user, account: account) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
                                    upsales_conversation_atual_id: conversation.id, ultimo_ponto: 'aguardando_volume')
  end
  let(:resync_url) { 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/resync' }

  def devolver!
    OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
    OperationalEngine::TakeoverService.devolver!(lead: lead, user_id: user.id)
    OperationalEngine::LeadEvent.where(lead: lead, event_type: 'intervencao_humana_encerrada').last.metadata['correlation_id']
  end

  describe 'agendamento pelo Devolver' do
    it 'uma devolução real agenda o turno de ressincronização com a identidade da devolução' do
      devolucao_id = devolver!

      expect(OperationalEngine::DevolucaoResyncJob).to have_been_enqueued.with(lead.lead_id, devolucao_id, kind_of(String))
    end

    it 'devolver um lead que já está com a Lavínia (no-op) não agenda nada' do
      OperationalEngine::TakeoverService.devolver!(lead: lead, user_id: user.id)

      expect(OperationalEngine::DevolucaoResyncJob).not_to have_been_enqueued
    end

    it 'falha ao agendar não desfaz a devolução' do
      allow(OperationalEngine::DevolucaoResyncJob).to receive(:perform_later).and_raise(StandardError, 'redis fora')

      devolver!

      expect(lead.reload.modo_atendimento).to eq('lavinia')
    end
  end

  describe '.current?' do
    it 'vale para a devolução vigente e deixa de valer depois de um novo Assumir' do
      devolucao_id = devolver!
      expect(described_class.current?(lead.reload, devolucao_id)).to be(true)
      expect(described_class.current?(lead, SecureRandom.uuid)).to be(false)

      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
      expect(described_class.current?(lead.reload, devolucao_id)).to be(false)
    end

    it 'deixa de valer depois de outra devolução (o instante do modo mudou)' do
      devolucao_id = devolver!
      devolvido_em = lead.reload.modo_atendimento_entrou_em.iso8601(6)
      travel_to(1.minute.from_now) { devolver! }

      expect(described_class.current?(lead.reload, devolucao_id, devolvido_em)).to be(false)
    end
  end

  describe '.call' do
    it 'pede ao up2-agents o turno silencioso da devolução vigente' do
      devolucao_id = devolver!
      stub = stub_request(:post, resync_url)
             .with(body: hash_including('chatwootConversationId' => conversation.display_id, 'devolucaoId' => devolucao_id))
             .to_return(status: 200, body: { ok: true, outcome: 'committed' }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.call(lead_id: lead.lead_id, devolucao_id: devolucao_id)

      expect(stub).to have_been_requested.once
    end

    it 'não chama o up2-agents quando a devolução já não é a vigente' do
      devolucao_id = devolver!
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)

      expect(described_class.call(lead_id: lead.lead_id, devolucao_id: devolucao_id)).to eq(:skipped)
      expect(a_request(:post, resync_url)).not_to have_been_made
    end

    it 'falha do turno levanta SyncError (para o job tentar de novo) sem desfazer a devolução' do
      devolucao_id = devolver!
      stub_request(:post, resync_url).to_return(status: 200, body: { ok: false, outcome: 'invalid-output' }.to_json,
                                                headers: { 'Content-Type' => 'application/json' })

      expect { described_class.call(lead_id: lead.lead_id, devolucao_id: devolucao_id) }
        .to raise_error(UpSales::Agents::ResyncConversationService::SyncError, 'invalid-output')
      expect(lead.reload).to have_attributes(modo_atendimento: 'lavinia', ultimo_ponto: 'aguardando_volume')
    end
  end

  describe 'DevolucaoResyncJob' do
    it 'esgotadas as tentativas, registra a falha e mantém o ultimo_ponto anterior' do
      devolucao_id = devolver!
      stub_request(:post, resync_url).to_return(status: 503, body: 'fora')

      perform_enqueued_jobs { OperationalEngine::DevolucaoResyncJob.perform_later(lead.lead_id, devolucao_id, nil) }

      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'ressincronizacao_devolucao_falhou')
      expect(event.metadata).to include('devolucao_id' => devolucao_id, 'ultimo_ponto_mantido' => 'aguardando_volume')
      expect(lead.reload).to have_attributes(modo_atendimento: 'lavinia', ultimo_ponto: 'aguardando_volume')
    end
  end
end
