require 'rails_helper'

describe OperationalEngineListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account) }

  it 'loga message_created sem gravar nada no Operational Engine' do
    event = Events::Base.new(:message_created, Time.zone.now, message: message)

    expect(Rails.logger).to receive(:info).with(/message_created.*"message_id":#{message.id}/)
    listener.message_created(event)

    expect(OperationalEngine::LeadEvent.count).to eq(0)
  end

  it 'loga message_updated com as chaves alteradas' do
    event = Events::Base.new(:message_updated, Time.zone.now, message: message, previous_changes: { 'status' => %w[sent delivered] })

    expect(Rails.logger).to receive(:info).with(/message_updated.*"status"/)
    listener.message_updated(event)
  end

  it 'loga assignee_changed' do
    event = Events::Base.new(:assignee_changed, Time.zone.now, conversation: conversation)

    expect(Rails.logger).to receive(:info).with(/assignee_changed.*"conversation_id":#{conversation.id}/)
    listener.assignee_changed(event)
  end
end
