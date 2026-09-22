require 'rails_helper'

RSpec.describe OperationalEngine::DispatcherJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:ready_tenant) do
    create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox)
  end
  let!(:sdr_slot) { create(:up_sales_agent_slot, account: account) }
  let(:other_account) { create(:account) }
  let!(:not_ready_tenant) { create(:up_sales_agent_tenant, account: other_account) } # sem whatsapp_inbox nem slot sdr

  it 'chama o Dispatcher so pras contas com whatsapp_inbox e slot sdr configurados' do
    expect(OperationalEngine::Dispatcher).to receive(:call).once.with(conta_id: account.id)

    described_class.perform_now
  end

  it 'pula uma conta com whatsapp_inbox mas sem slot sdr ativo' do
    account_sem_slot = create(:account)
    create(:up_sales_agent_tenant, account: account_sem_slot, whatsapp_inbox: inbox)

    expect(OperationalEngine::Dispatcher).not_to receive(:call).with(conta_id: account_sem_slot.id)

    described_class.perform_now
  end

  it 'nao deixa a falha de uma conta impedir as outras' do
    third_account = create(:account)
    create(:up_sales_agent_tenant, account: third_account, whatsapp_inbox: inbox)
    create(:up_sales_agent_slot, account: third_account)

    allow(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: account.id).and_raise('boom')
    expect(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: third_account.id)
    expect(ChatwootExceptionTracker).to receive(:new).and_call_original

    expect { described_class.perform_now }.not_to raise_error
  end
end
