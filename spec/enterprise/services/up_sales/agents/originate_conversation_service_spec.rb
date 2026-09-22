require 'rails_helper'

RSpec.describe UpSales::Agents::OriginateConversationService do
  let(:account) { create(:account) }
  let(:agent_tenant) { create(:up_sales_agent_tenant, account: account, prospecting_agent_id: 77) }
  let(:contact) { create(:contact, account: account, name: 'João', phone_number: '+5513991234567') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox, contact_inbox: contact_inbox) }

  def perform
    described_class.new(agent_tenant: agent_tenant, conversation: conversation, contact_inbox: contact_inbox).perform
  end

  def stub_originate(status: 200, body: { ok: true, outcome: 'posted' })
    stub_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'manda os IDs certos pro up2-agents' do
    stub_originate

    perform

    expect(
      a_request(:post, 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/originate')
        .with(
          headers: { 'Authorization' => "Bearer #{agent_tenant.api_key}" },
          body: hash_including(
            'agentId' => '77',
            'chatwootAccountId' => account.id,
            'chatwootConversationId' => conversation.display_id,
            'chatwootInboxId' => inbox.id,
            'chatwootContactId' => contact.id,
            'contactInboxId' => contact_inbox.id,
            'contactName' => 'João',
            'contactPhone' => '+5513991234567'
          )
        )
    ).to have_been_made
  end

  it 'retorna o corpo da resposta quando ok:true' do
    stub_originate(body: { ok: true, outcome: 'posted' })

    expect(perform).to eq('ok' => true, 'outcome' => 'posted')
  end

  it 'levanta SyncError quando a resposta HTTP falha' do
    stub_originate(status: 500, body: { error: 'boom' })

    expect { perform }.to raise_error(described_class::SyncError, 'boom')
  end

  it 'levanta SyncError quando ok:false (ex.: agente em modo teste)' do
    stub_originate(body: { ok: false, outcome: 'blocked' })

    expect { perform }.to raise_error(described_class::SyncError, 'origination recusada')
  end
end
