require 'rails_helper'

# CP-03 -- achado novo (fora dos IDs da auditoria): o up2-agents manda o display_id do Chatwoot como
# conversation_id; a resolução precisa usar display_id, nunca a PK global.
RSpec.describe OperationalEngine::Tools::ResolveLeadFromConversation do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number) }

  it 'resolve pela display_id (o id que o bot/up2-agents usa), não pela PK' do
    # Conversas em outra conta empurram a sequência da PK: a conversa desta conta passa a ter
    # id != display_id, que é o caso real em produção.
    create_list(:conversation, 3, account: create(:account))
    conversation = create(:conversation, account: account, contact: contact)
    expect(conversation.id).not_to eq(conversation.display_id)

    expect(described_class.call(account: account, conversation_id: conversation.display_id)).to eq(lead)
    expect { described_class.call(account: account, conversation_id: conversation.id) }.to raise_error(described_class::NotFound)
  end

  it 'nunca resolve conversa de outra conta, mesmo com o mesmo display_id' do
    other_account = create(:account)
    create(:conversation, account: account, contact: contact)
    foreign = create(:conversation, account: other_account, contact: create(:contact, account: other_account, phone_number: '+5511999990000'))

    expect { described_class.call(account: account, conversation_id: foreign.display_id + 100) }.to raise_error(described_class::NotFound)
  end
end
