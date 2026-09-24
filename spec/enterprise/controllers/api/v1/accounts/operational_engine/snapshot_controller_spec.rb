require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationalEngine::Snapshot', type: :request do
  let(:account) { create(:account) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, nome: 'Danilo') }

  let(:valid_headers) { { 'Authorization' => "Bearer #{agent_tenant.engine_api_key}" } }

  describe 'GET health' do
    it 'usa a mesma autenticação servidor-a-servidor do Contrato B (S-5)' do
      get "/api/v1/accounts/#{account.id}/operational_engine/health", as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'chave inválida')
    end

    it 'confirma que o Supabase está alcançável, não só que a chave é válida' do
      get "/api/v1/accounts/#{account.id}/operational_engine/health", headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true)
    end
  end

  describe 'GET snapshot' do
    it 'devolve o Snapshot (§12.3) do lead da conversa' do
      get "/api/v1/accounts/#{account.id}/operational_engine/snapshot",
          params: { conversation_id: conversation.display_id }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['ok']).to eq(true)
      expect(body['snapshot']['identidade']['nome']).to eq('Danilo')
      expect(body['snapshot']['identidade']['telefone']).to eq(contact.phone_number)
      expect(body['snapshot']['source']).to eq('engine')
    end

    it 'devolve ok:false quando a conversa não resolve nenhum lead' do
      get "/api/v1/accounts/#{account.id}/operational_engine/snapshot",
          params: { conversation_id: -1 }, headers: valid_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('ok' => false, 'reason' => 'conversa não encontrada')
    end

    it 'rejeita sem autenticação, igual ao ToolsController' do
      get "/api/v1/accounts/#{account.id}/operational_engine/snapshot",
          params: { conversation_id: conversation.display_id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # CP-03 -- P1-017-01, P1-017-02, P1-021-03, P1-022-02.
  describe 'GET snapshot com o disparador do turno' do
    let(:path) { "/api/v1/accounts/#{account.id}/operational_engine/snapshot" }

    def incoming(text, conv = conversation)
      create(:message, account: account, inbox: conv.inbox, conversation: conv, message_type: 'incoming', sender: contact, content: text)
    end

    def fetch(**params)
      get path, params: { conversation_id: conversation.display_id, **params }, headers: valid_headers, as: :json
      response.parsed_body
    end

    it 'com duas mensagens, cada turno recebe exatamente o seu disparador como mensagem_atual' do
      primeira = incoming('quero saber o preço')
      segunda = incoming('e vocês atendem Santos?')

      body_primeira = fetch(message_id: primeira.id)
      body_segunda = fetch(message_id: segunda.id)

      expect(body_primeira['snapshot']['mensagem_atual']).to include('message_id' => primeira.id.to_s, 'texto' => 'quero saber o preço')
      expect(body_primeira['snapshot']['mensagem_atual']['timestamp']).to eq(primeira.created_at.iso8601)
      # nada que chegou depois do disparador vaza para o turno anterior
      expect(body_primeira['snapshot']['mensagens_recentes_relevantes'].pluck('message_id')).to eq([primeira.id.to_s])
      expect(body_segunda['snapshot']['mensagem_atual']['message_id']).to eq(segunda.id.to_s)
      # o histórico do segundo turno termina no seu disparador e inclui o anterior (o widget pode ter
      # criado mensagens próprias no meio -- ex.: coleta de e-mail -- que também são conversa pública)
      recentes = body_segunda['snapshot']['mensagens_recentes_relevantes'].pluck('message_id')
      expect(recentes.first(1) + recentes.last(1)).to eq([primeira.id.to_s, segunda.id.to_s])
    end

    it 'recusa uma mensagem que não pertence à conversa' do
      outra_conversa = create(:conversation, account: account, contact: contact)
      alheia = incoming('oi', outra_conversa)

      body = fetch(message_id: alheia.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['reason']).to eq('mensagem não pertence à conversa')
    end

    it 'o mesmo lead produz contextos diferentes conforme o disparador' do
      mensagem = incoming('oi')

      contextos = %w[conversa recuperacao agenda].map do |contexto|
        fetch(message_id: mensagem.id, contexto_execucao: contexto)['snapshot']['continuidade']['contexto_execucao']
      end

      expect(contextos).to eq(%w[conversa recuperacao agenda])
    end

    it 'recusa contexto_execucao desconhecido' do
      fetch(contexto_execucao: 'qualquer_coisa')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    describe 'primeiro contato (originação)' do
      before do
        lead.update!(etapa_prospect: 'backlog')
        conversation.update!(additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
      end

      let(:activation) { OperationalEngine::OriginationActivation.for(conversation.reload) }

      it 'com a ativação autorizada desta conversa devolve contexto primeiro_contato e sem mensagem atual' do
        body = fetch(contexto_execucao: 'primeiro_contato', activation_id: activation.activation_id)

        expect(response).to have_http_status(:ok)
        expect(body['snapshot']['continuidade']['contexto_execucao']).to eq('primeiro_contato')
        expect(body['snapshot']['mensagem_atual']).to be_nil
      end

      it 'recusa primeiro contato sem a ativação certa ou com ativação já usada' do
        fetch(contexto_execucao: 'primeiro_contato', activation_id: SecureRandom.uuid)
        expect(response).to have_http_status(:unprocessable_entity)

        activation.transition!('consumed', message_id: 1)
        fetch(contexto_execucao: 'primeiro_contato', activation_id: activation.activation_id)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
