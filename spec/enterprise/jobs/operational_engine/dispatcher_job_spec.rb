require 'rails_helper'

RSpec.describe OperationalEngine::DispatcherJob do
  def whatsapp_inbox_for(account)
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end

  let(:account) { create(:account) }
  let!(:ready_tenant) do
    create(:up_sales_agent_tenant, account: account, whatsapp_inbox: whatsapp_inbox_for(account))
  end
  let!(:sdr_slot) { create(:up_sales_agent_slot, account: account) }
  let(:other_account) { create(:account) }
  let!(:not_ready_tenant) { create(:up_sales_agent_tenant, account: other_account) } # sem whatsapp_inbox nem slot sdr

  it 'chama o Dispatcher so pras contas com whatsapp_inbox e slot sdr configurados' do
    expect(OperationalEngine::Dispatcher).to receive(:call).once.with(conta_id: account.id)

    described_class.perform_now
  end

  # CP-13 -- P1-VAL-12 (SSOT §15.6): recovery na mesma fila por inbox, no mesmo tick, depois da
  # primeira abordagem.
  it 'chama o RecoveryDispatcher depois do Dispatcher, na mesma conta' do
    expect(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: account.id).ordered
    expect(OperationalEngine::RecoveryDispatcher).to receive(:call).with(conta_id: account.id).ordered

    described_class.perform_now
  end

  it 'pula uma conta com whatsapp_inbox mas sem slot sdr ativo' do
    account_sem_slot = create(:account)
    create(:up_sales_agent_tenant, account: account_sem_slot, whatsapp_inbox: whatsapp_inbox_for(account_sem_slot))

    expect(OperationalEngine::Dispatcher).not_to receive(:call).with(conta_id: account_sem_slot.id)

    described_class.perform_now
  end

  # CP-07 -- P1-027-01.
  it 'nao chama o Dispatcher quando o slot sdr foi desabilitado (mesmo com o id remoto preservado)' do
    sdr_slot.update!(enabled: false, up2_agents_agent_id: '77')

    expect(OperationalEngine::Dispatcher).not_to receive(:call)

    described_class.perform_now
  end

  it 'nao deixa a falha de uma conta impedir as outras' do
    third_account = create(:account)
    create(:up_sales_agent_tenant, account: third_account, whatsapp_inbox: whatsapp_inbox_for(third_account))
    create(:up_sales_agent_slot, account: third_account)

    allow(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: account.id).and_raise('boom')
    expect(OperationalEngine::Dispatcher).to receive(:call).with(conta_id: third_account.id)
    expect(ChatwootExceptionTracker).to receive(:new).and_call_original

    expect { described_class.perform_now }.not_to raise_error
  end
end
