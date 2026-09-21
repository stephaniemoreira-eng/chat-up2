require 'rails_helper'

RSpec.describe OperationalEngine::ProcessMessageJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: 'incoming') }

  it 'reprocesses the persisted message through the Engine boundary' do
    expect(OperationalEngine::MessageProcessor).to receive(:call).with(message)

    described_class.perform_now(message.id)
  end

  it 'is a no-op when the message no longer exists' do
    expect(OperationalEngine::MessageProcessor).not_to receive(:call)

    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
