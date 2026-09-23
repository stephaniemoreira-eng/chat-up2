require 'rails_helper'

RSpec.describe 'Enterprise Conversation Messages API', type: :request do
  let!(:account) { create(:account) }

  describe 'DELETE /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:message) { create(:message, account: account, content: 'Secret original content') }
    let(:conversation) { message.conversation }
    let(:agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: conversation.inbox, user: agent)
    end

    it 'soft deletes the message and records an audit log with the original content' do
      expect do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.to change(Enterprise::AuditLog, :count).by(1)

      audit_log = Enterprise::AuditLog.where(auditable_type: 'Message', action: 'destroy').last

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(message.reload.content).to eq 'This message was deleted'
        expect(message.reload.deleted).to be true
        expect(audit_log.auditable_id).to eq(message.id)
        expect(audit_log.user_id).to eq(agent.id)
        expect(audit_log.associated_id).to eq(account.id)
        expect(audit_log.remote_address).to be_present
        expect(audit_log.audited_changes['content']).to eq('Secret original content')
        expect(audit_log.audited_changes['conversation_id']).to eq(message.conversation_id)
        expect(audit_log.audited_changes['display_id']).to eq(conversation.display_id)
        expect(audit_log.audited_changes['inbox_id']).to eq(message.inbox_id)
      end
    end

    it 'does not create an audit log when the message id is invalid' do
      expect do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/99999",
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(Enterprise::AuditLog, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not create a duplicate audit log when an already-deleted message is deleted again' do
      path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}"

      delete path, headers: agent.create_new_auth_token, as: :json
      expect(Enterprise::AuditLog.where(auditable_type: 'Message', action: 'destroy').count).to eq(1)

      expect do
        delete path, headers: agent.create_new_auth_token, as: :json
      end.not_to change(Enterprise::AuditLog, :count)
    end
  end

  # CP-01: autorização final do Operational Engine no post público do AgentBot (P0-022-02/P0-024-01).
  describe 'POST /api/v1/accounts/{account.id}/conversations/:conversation_id/messages como AgentBot' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
    let(:agent_bot) { create(:agent_bot) }
    let!(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog',
                                      etapa_entrou_em: 1.hour.ago)
    end
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox),
                            additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
    end
    let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }

    before do
      create(:up_sales_agent_tenant, account: account)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    end

    it 'grava a abertura quando o lead continua elegível' do
      post path, params: { content: 'Oi!' }, headers: { api_access_token: agent_bot.access_token.token }, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.messages.outgoing.count).to eq(1)
    end

    it 'recusa com 409 e não grava nada quando o lead ficou inelegível antes do post' do
      lead.update!(nao_contatar: true)

      post path, params: { content: 'Oi!' }, headers: { api_access_token: agent_bot.access_token.token }, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('operational_engine_blocked')
      expect(response.parsed_body['reason']).to include('nao_contatar')
      expect(conversation.messages.count).to eq(0)
    end

    it 'nota privada do bot não passa pelo gate' do
      lead.update!(nao_contatar: true)

      post path, params: { content: 'nota', private: true }, headers: { api_access_token: agent_bot.access_token.token }, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
