require 'rails_helper'

# CP-16B -- P2-VAL-20: pedido do turno silencioso de ressincronização pós-devolução ao up2-agents.
RSpec.describe UpSales::Agents::ResyncConversationService do
  let(:account) { create(:account) }
  let(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:url) { 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/resync' }

  def perform
    described_class.new(agent_tenant: agent_tenant, conversation: conversation, devolucao_id: 'dev-1').perform
  end

  def stub_resync(status: 200, body: { ok: true, outcome: 'committed' })
    stub_request(:post, url).to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'manda a conversa e a identidade da devolução, com a chave do tenant' do
    stub_resync

    perform

    expect(
      a_request(:post, url).with(
        headers: { 'Authorization' => "Bearer #{agent_tenant.api_key}" },
        body: hash_including('chatwootAccountId' => account.id, 'chatwootConversationId' => conversation.display_id, 'devolucaoId' => 'dev-1')
      )
    ).to have_been_made.once
  end

  it '"unchanged" (nada novo a gravar) é sucesso' do
    stub_resync(body: { ok: true, outcome: 'unchanged' })

    expect(perform).to include('ok' => true, 'outcome' => 'unchanged')
  end

  it 'turno recusado ou HTTP de erro levanta SyncError' do
    stub_resync(body: { ok: false, outcome: 'blocked' })
    expect { perform }.to raise_error(described_class::SyncError, 'blocked')

    stub_resync(status: 500, body: { error: 'boom' })
    expect { perform }.to raise_error(described_class::SyncError, 'boom')
  end

  it 'up2-agents fora do ar vira SyncError (o job tenta de novo)' do
    stub_request(:post, url).to_raise(Errno::ECONNREFUSED)

    expect { perform }.to raise_error(described_class::SyncError, /up2-agents indisponível/)
  end
end
