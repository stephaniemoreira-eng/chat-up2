require 'rails_helper'

RSpec.describe OperationalEngine::DispatcherJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:ready_tenant) do
    create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox, prospecting_agent_id: 77)
  end
  let(:other_account) { create(:account) }
  let!(:not_ready_tenant) { create(:up_sales_agent_tenant, account: other_account) } # sem whatsapp_inbox/prospecting_agent_id

  it 'chama o Dispatcher so pras contas com whatsapp_inbox e prospecting_agent_id configurados' do
    expect(OperationalEngine::Dispatcher).to receive(:call).once.with(conta_id: account.id)

    described_class.perform_now
  end

  it 'nao deixa a falha de uma conta impedir as outras' do
    third_account = create(:account)
    create(:up_sales_agent_tenant, account: third_account, whatsapp_inbox: inbox, prospecting_agent_id: 88)

    allow(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: account.id).and_raise('boom')
    expect(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: third_account.id)
    expect(ChatwootExceptionTracker).to receive(:new).and_call_original

    expect { described_class.perform_now }.not_to raise_error
  end
end
