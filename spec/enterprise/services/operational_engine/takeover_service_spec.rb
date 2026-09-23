require 'rails_helper'

RSpec.describe OperationalEngine::TakeoverService do
  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: 1, telefone: "+551399#{rand(1_000_000..9_999_999)}"
    }.merge(overrides))
  end

  describe '.assumir! (teste 28.19)' do
    it 'poe o lead em modo humano com o responsavel e o timestamp' do
      lead = build_lead
      travel_to(Time.zone.parse('2026-09-21 10:00:00')) do
        described_class.assumir!(lead: lead, user_id: 42)
      end

      lead.reload
      expect(lead.modo_atendimento).to eq('humano')
      expect(lead.responsavel_atual_id).to eq(42)
      expect(lead.modo_atendimento_entrou_em).to eq(Time.zone.parse('2026-09-21 10:00:00'))
    end

    it 'zera aguardando_resposta e desativa recovery -- nenhum envio automatico pode estar pendente' do
      lead = build_lead(aguardando_resposta: true, recuperacao_status: 'ativa', proxima_recuperacao_em: 1.day.from_now)

      described_class.assumir!(lead: lead, user_id: 42)

      lead.reload
      expect(lead.aguardando_resposta).to be(false)
      expect(lead.recuperacao_status).to eq('inativa')
      expect(lead.proxima_recuperacao_em).to be_nil
    end

    it 'nao mexe em etapa_prospect, qualificacao_status ou frente_operacional' do
      lead = build_lead(etapa_prospect: 'qualificado', qualificacao_status: 'qualificado', frente_operacional: 'comercial')

      described_class.assumir!(lead: lead, user_id: 42)

      lead.reload
      expect(lead.etapa_prospect).to eq('qualificado')
      expect(lead.qualificacao_status).to eq('qualificado')
      expect(lead.frente_operacional).to eq('comercial')
    end

    it 'grava intervencao_humana_iniciada' do
      lead = build_lead

      described_class.assumir!(lead: lead, user_id: 42)

      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'intervencao_humana_iniciada')
      expect(event).to be_present
      expect(event.source).to eq('human')
      expect(event.metadata['responsavel_atual_id']).to eq(42)
    end

    it 'e idempotente: assumir de novo nao reescreve modo_atendimento_entrou_em nem duplica o evento' do
      lead = build_lead
      first_entrou_em = travel_to(Time.zone.parse('2026-09-21 10:00:00')) do
        described_class.assumir!(lead: lead, user_id: 42)
        lead.reload.modo_atendimento_entrou_em
      end

      travel_to(Time.zone.parse('2026-09-21 10:05:00')) do
        described_class.assumir!(lead: lead, user_id: 99)
      end

      lead.reload
      expect(lead.modo_atendimento_entrou_em).to eq(first_entrou_em)
      expect(lead.responsavel_atual_id).to eq(42)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'intervencao_humana_iniciada').count).to eq(1)
    end
  end

  describe '.devolver! (teste 28.22)' do
    it 'volta o lead pra lavinia e limpa o responsavel' do
      lead = build_lead(modo_atendimento: 'humano', responsavel_atual_id: 42)

      described_class.devolver!(lead: lead)

      lead.reload
      expect(lead.modo_atendimento).to eq('lavinia')
      expect(lead.responsavel_atual_id).to be_nil
    end

    it 'grava intervencao_humana_encerrada com o responsavel que estava saindo' do
      lead = build_lead(modo_atendimento: 'humano', responsavel_atual_id: 42)

      described_class.devolver!(lead: lead)

      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'intervencao_humana_encerrada')
      expect(event.metadata['responsavel_atual_id']).to eq(42)
    end

    it 'devolver um lead que ja esta em lavinia e um no-op' do
      lead = build_lead(modo_atendimento: 'lavinia')

      described_class.devolver!(lead: lead)

      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'intervencao_humana_encerrada').count).to eq(0)
    end
  end

  describe 'sincronizacao visual do Kanban (Fase 5, §20.1)' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }

    def build_linked_lead(**overrides)
      OperationalEngine::Lead.create!({
        conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id
      }.merge(overrides))
    end

    it 'assumir! troca a tag do card de lavinia pra humano imediatamente' do
      lead = build_linked_lead(modo_atendimento: 'lavinia')
      OperationalEngine::SalesProjectionSync.call(lead)

      described_class.assumir!(lead: lead, user_id: 42)

      sales_lead = Sales::Lead.find_by(contact_id: contact.id)
      expect(sales_lead.custom_attributes['engine_tags']).to eq(['humano'])
    end

    it 'devolver! troca a tag do card de volta pra lavinia' do
      lead = build_linked_lead(modo_atendimento: 'humano', responsavel_atual_id: 42)
      OperationalEngine::SalesProjectionSync.call(lead)

      described_class.devolver!(lead: lead)

      sales_lead = Sales::Lead.find_by(contact_id: contact.id)
      expect(sales_lead.custom_attributes['engine_tags']).to eq(['lavinia'])
    end

    it 'assumir! num lead ja humano (no-op) nao levanta erro mesmo sem card ainda' do
      lead = build_linked_lead(modo_atendimento: 'humano', responsavel_atual_id: 42)

      expect { described_class.assumir!(lead: lead, user_id: 99) }.not_to raise_error
    end

    it 'tambem sincroniza o card Comercial (Fase 9) quando ja existe oportunidade' do
      lead = build_linked_lead(modo_atendimento: 'lavinia', etapa_comercial: 'oportunidade')

      described_class.assumir!(lead: lead, user_id: 42)

      comercial_card = Sales::Lead.joins(:pipeline).find_by(contact_id: contact.id, sales_pipelines: { engine_kind: 'comercial' })
      expect(comercial_card).to be_present
    end
  end

  # CP-05 -- P1-026-02 (SSOT §3.2, §23.3, §28.40): falha de projeção depois da transição não deixa o
  # card stale -- retry/no-op do próprio endpoint (ou o reconciliador) converge, sem duplicar evento.
  describe 'reconciliacao da projecao (P1-026-02)' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }

    def prospect_tags(lead)
      Sales::Lead.joins(:pipeline).find_by!(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'prospect' })
                 .custom_attributes['engine_tags']
    end

    def break_projection!
      allow(OperationalEngine::SalesProjectionSync).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'banco nativo fora')
    end

    def heal_projection!
      allow(OperationalEngine::SalesProjectionSync).to receive(:call).and_call_original
    end

    it 'assumir: projeção falha, repetir Assumir (no-op) converge o card para HUMANO sem duplicar a intervenção' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110020', upsales_contact_id: contact.id)
      OperationalEngine::SalesProjectionSync.call(lead)
      break_projection!

      expect { described_class.assumir!(lead: lead, user_id: 42) }.not_to raise_error
      expect(lead.reload.modo_atendimento).to eq('humano')
      expect(OperationalEngine::ProjectionRequest.find(lead.lead_id)).to be_status_pendente

      heal_projection!
      described_class.assumir!(lead: lead, user_id: 42)

      expect(prospect_tags(lead)).to eq(['humano'])
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'intervencao_humana_iniciada').count).to eq(1)
      expect(OperationalEngine::ProjectionRequest.find(lead.lead_id)).to be_status_sincronizado
    end

    it 'devolver: projeção falha, o reconciliador converge o card para LAVÍNIA sem duplicar o evento' do
      lead = OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991110021', upsales_contact_id: contact.id,
                                             modo_atendimento: 'humano', responsavel_atual_id: 42)
      OperationalEngine::SalesProjectionSync.call(lead)
      break_projection!
      described_class.devolver!(lead: lead)

      heal_projection!
      travel(5.minutes) { OperationalEngine::ProjectionReconcileJob.perform_now }

      expect(prospect_tags(lead)).to eq(['lavinia'])
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'intervencao_humana_encerrada').count).to eq(1)
    end
  end

  # CP-05 -- P1-018-01: o handoff real pode deixar o responsável Comercial pendente (lacuna do SSOT);
  # Assumir preenche o responsável (§18.2) sem abrir uma segunda intervenção.
  describe 'assumir um lead com responsável pendente do handoff' do
    it 'grava o usuário como responsável e registra responsavel_alterado' do
      lead = build_lead(modo_atendimento: 'humano', responsavel_atual_id: nil, frente_operacional: 'comercial',
                        etapa_comercial: 'oportunidade', motivo_handoff: 'avanco_comercial')

      described_class.assumir!(lead: lead, user_id: 42)

      expect(lead.reload.responsavel_atual_id).to eq(42)
      event = OperationalEngine::LeadEvent.find_by(lead: lead, event_type: 'responsavel_alterado')
      expect(event.metadata).to include('de' => nil, 'para' => 42)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'intervencao_humana_iniciada')).to be_empty
    end
  end

  # CP-06 -- P1-026-01, P2-026-01, P2-026-02 (SSOT §7.3, §7.4, §18.2, §18.3, §28.19, §28.22).
  describe 'devolução com sincronização prévia e timeline canônica (CP-06)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, phone_number: '+5513991240001') }
    let(:user) { create(:user, account: account, role: :agent) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:lead) do
      OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
                                      upsales_conversation_atual_id: conversation.id, etapa_prospect: 'em_conversa',
                                      ultima_interacao_em: 3.hours.ago, ultimo_ponto: 'perguntou sobre coleta')
    end

    before do
      create(:agent_bot_inbox, inbox: inbox)
      create(:inbox_member, user: user, inbox: inbox)
    end

    def message!(type, sender, at:)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, sender: sender, created_at: at)
    end

    def events(type)
      OperationalEngine::LeadEvent.where(lead: lead, event_type: type).order(:event_at, :id)
    end

    it '28.19: assumir para a Lavínia na conversa do canal, cancela a abertura autorizada e registra modo/responsável' do
      conversation.update!(status: :pending, additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))

      described_class.assumir!(lead: lead, user_id: user.id)

      expect(conversation.reload).to be_open
      expect(OperationalEngine::OriginationActivation.for(conversation).status).to eq('cancelled')
      modo = events('modo_atendimento_alterado').last.metadata
      expect(modo).to include('de' => 'lavinia', 'para' => 'humano', 'motivo' => 'assumir', 'executado_por' => user.id)
      expect(events('responsavel_alterado').last.metadata).to include('de' => nil, 'para' => user.id, 'executado_por' => user.id)
      expect(events('intervencao_humana_iniciada').last.metadata['correlation_id']).to eq(modo['correlation_id'])
    end

    it '28.22: sincroniza ANTES de reativar e só então devolve a conversa para a Lavínia' do
      described_class.assumir!(lead: lead, user_id: user.id)
      travel(10.minutes)
      lead_msg = message!(:incoming, contact, at: 2.minutes.ago)
      human_msg = message!(:outgoing, user, at: 1.minute.ago)
      allow(OperationalEngine::DevolucaoSync).to receive(:call).and_wrap_original do |original, locked_lead|
        expect(locked_lead.reload.modo_atendimento).to eq('humano')
        original.call(locked_lead)
      end

      described_class.devolver!(lead: lead, user_id: user.id)

      expect(lead.reload.modo_atendimento).to eq('lavinia')
      expect(lead.ultima_interacao_em).to be_within(1.second).of(lead_msg.created_at)
      sync = events('intervencao_humana_encerrada').last.metadata['sincronizacao']
      expect(sync).to include('conversation_id' => conversation.id, 'mensagens_na_intervencao' => 2, 'ultimo_ponto' => 'perguntou sobre coleta')
      expect(sync['ultima_mensagem_lead']['message_id']).to eq(lead_msg.id)
      expect(sync['ultima_mensagem_humana']).to include('message_id' => human_msg.id, 'user_id' => user.id)
      expect(conversation.reload).to be_pending
    end

    it 'devolver grava modo e responsável com de/para/motivo/executado_por (timeline reconstruível)' do
      described_class.assumir!(lead: lead, user_id: user.id)
      described_class.devolver!(lead: lead, user_id: 7)

      modo = events('modo_atendimento_alterado').last.metadata
      expect(modo).to include('de' => 'humano', 'para' => 'lavinia', 'motivo' => 'devolver', 'executado_por' => 7)
      expect(events('responsavel_alterado').last.metadata).to include('de' => user.id, 'para' => nil, 'motivo' => 'devolver')
      expect(events('intervencao_humana_encerrada').last.metadata).to include('responsavel_atual_id' => user.id, 'executado_por' => 7)
      expect(events('modo_atendimento_alterado').map { |event| event.metadata['para'] }).to eq(%w[humano lavinia])
    end

    it 'sincronização falha: lead continua humano, responsável mantido, nenhum evento e nada projetado' do
      described_class.assumir!(lead: lead, user_id: user.id)
      allow(OperationalEngine::DevolucaoSync).to receive(:call).and_raise(OperationalEngine::DevolucaoSync::SyncError, 'chatwoot fora')

      expect { described_class.devolver!(lead: lead, user_id: user.id) }.to raise_error(OperationalEngine::DevolucaoSync::SyncError)

      expect(lead.reload.modo_atendimento).to eq('humano')
      expect(lead.responsavel_atual_id).to eq(user.id)
      expect(events('intervencao_humana_encerrada')).to be_empty
      expect(conversation.reload).to be_open
    end

    it 'conversa atual de outro contato é divergência: a devolução não acontece' do
      described_class.assumir!(lead: lead, user_id: user.id)
      lead.update!(upsales_conversation_atual_id: create(:conversation, account: account, inbox: inbox).id)

      expect { described_class.devolver!(lead: lead, user_id: user.id) }
        .to raise_error(OperationalEngine::DevolucaoSync::SyncError, /outro contato/)
      expect(lead.reload.modo_atendimento).to eq('humano')
    end

    it 'timers antigos não ressuscitam: devolver não restaura aguardando_resposta nem recovery' do
      described_class.assumir!(lead: lead, user_id: user.id)
      lead.update!(aguardando_resposta: true, recuperacao_status: 'ativa', proxima_recuperacao_em: 1.hour.from_now)

      described_class.devolver!(lead: lead, user_id: user.id)

      lead.reload
      expect(lead.aguardando_resposta).to be(false)
      expect(lead.recuperacao_status).to eq('inativa')
      expect(lead.proxima_recuperacao_em).to be_nil
    end

    it 'falha na projeção da conversa depois do Devolver é reconciliada sem duplicar a intervenção' do
      described_class.assumir!(lead: lead, user_id: user.id)
      allow(OperationalEngine::ConversationModeProjection).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'banco nativo fora')

      described_class.devolver!(lead: lead, user_id: user.id)
      expect(conversation.reload).to be_open

      allow(OperationalEngine::ConversationModeProjection).to receive(:call).and_call_original
      travel(5.minutes) { OperationalEngine::ProjectionReconcileJob.perform_now }

      expect(conversation.reload).to be_pending
      expect(events('intervencao_humana_encerrada').count).to eq(1)
      expect(events('modo_atendimento_alterado').count).to eq(2)
    end
  end

  describe 'concorrencia (teste 28.23)' do
    # Prova o mecanismo (row lock via with_lock), não a corrida em si: um teste com Threads reais
    # contra o pool de conexões de teste é flaky por natureza (timing, tamanho do pool) e não há
    # dispatcher real ainda (Fase 6/7) pra simular a corrida verdadeira. O que 28.23 exige --
    # "revalidação deve bloquear envio automático" -- depende de todo leitor concorrente tomar o
    # mesmo lock, o que é responsabilidade de quem for escrito depois (o dispatcher), não deste
    # serviço; aqui garantimos que o lado do Assumir já faz a sua parte.
    it 'assumir! toma lock de linha no lead antes de decidir' do
      lead = build_lead

      expect(lead).to receive(:with_lock).and_call_original

      described_class.assumir!(lead: lead, user_id: 1)
    end
  end
end
