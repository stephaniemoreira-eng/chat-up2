require 'rails_helper'

# CP-01 -- P0-022-02, P0-024-01, P0-018-01 (lado envio), SSOT §12.4/§19/§23.2.
RSpec.describe OperationalEngine::OutboundSendGate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:agent_bot) { create(:agent_bot) }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account) }
  let!(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog',
                                    etapa_entrou_em: 1.hour.ago, upsales_contact_id: contact.id)
  end
  # Conversa como o Dispatcher a deixa depois do claim: ativação "authorized", ninguém falou ainda.
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                          additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
  end

  def post_bot_message(content: 'Oi, aqui é a Lavínia da Lava e Pronto!')
    described_class.authorize!(conversation: conversation) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                       sender: agent_bot, content: content)
    end
  end

  def incoming!(at: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming',
                     sender: contact, created_at: at)
  end

  def expect_blocked(reason_pattern)
    expect { post_bot_message }.to raise_error(described_class::Blocked) { |e| expect(e.reason).to match(reason_pattern) }
    expect(conversation.messages.outgoing.where(sender: agent_bot)).to be_empty
  end

  def activation
    OperationalEngine::OriginationActivation.for(conversation.reload)
  end

  describe '.applies?' do
    it 'só vale pra mensagem pública do AgentBot em conta com Operational Engine' do
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: {})).to be(true)
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: { message_type: 'template' })).to be(true)
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: { private: true })).to be(false)
      expect(described_class.applies?(conversation: conversation, sender: create(:user, account: account), params: {})).to be(false)

      agent_tenant.destroy!
      expect(described_class.applies?(conversation: conversation, sender: agent_bot, params: {})).to be(false)
    end
  end

  describe 'abertura do Dispatcher (ativação authorized)' do
    it 'deixa sair quando o lead continua elegível e consome a ativação' do
      message = post_bot_message

      expect(message).to be_persisted
      expect(activation.status).to eq('consumed')
      expect(activation.conversation.additional_attributes.dig('up_sales_origination', 'message_id')).to eq(message.id)
    end

    it 'bloqueia quando nao_contatar entrou depois do claim' do
      lead.update!(nao_contatar: true)

      expect_blocked(/nao_contatar/)
      expect(activation.status).to eq('authorized')
    end

    it 'bloqueia quando um humano assumiu depois do claim' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: create(:user, account: account).id)

      expect_blocked(/atendimento_humano/)
    end

    it 'bloqueia quando o lead virou cliente atual' do
      lead.update!(relacao_atual: 'cliente_atual')

      expect_blocked(/cliente_atual/)
    end

    it 'bloqueia quando o lead foi encerrado' do
      lead.update!(lead_status: 'encerrado', motivo_encerramento: 'sem_interesse')

      expect_blocked(/lead_encerrado/)
    end

    it 'bloqueia quando o lead saiu do Backlog (estado incompatível)' do
      lead.update!(etapa_prospect: 'em_conversa')

      expect_blocked(/fora_do_backlog/)
    end

    it 'bloqueia quando outra ativação já teve a primeira abordagem confirmada' do
      lead.update!(primeiro_contato_em: 1.minute.ago)

      expect_blocked(/primeira_abordagem_ja_enviada/)
    end

    it 'bloqueia quando outra conversa do mesmo contato já consumiu uma ativação (ativação concorrente)' do
      other = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                    additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
      OperationalEngine::OriginationActivation.for(other).transition!('consumed', message_id: 1)

      expect_blocked(/ativacao_concorrente/)
    end

    it 'fato novo gravado enquanto o gate esperava o lock vence a ação preparada' do
      # O gate carrega o lead (fotografia elegível); antes de ele tomar o lock, o opt-out é
      # persistido por outro processo. with_lock relê a linha -- o fato novo tem que vencer.
      allow(OperationalEngine::LeadRepository).to receive(:find_by_telefone).and_wrap_original do |original, **kwargs|
        stale = original.call(**kwargs)
        OperationalEngine::Lead.find(stale.lead_id).update!(nao_contatar: true)
        stale
      end

      expect_blocked(/nao_contatar/)
    end

    it 'telefone que deixou de ser E.164 válido torna o lead inelegível para a abertura (CP-02, P1-024-04)' do
      lead.update_column(:telefone, '13991234567') # rubocop:disable Rails/SkipsModelValidations

      expect(OperationalEngine::OutboundEligibility.origination_blockers(lead.reload)).to include('telefone_invalido')
    end

    # CP-02 -- P0-022-01: retry/concorrência da mesma ativação depois de o lead já estar Contatado.
    it 'abertura já gravada e contato sem responder: nova mensagem automática fora da janela é bloqueada' do
      post_bot_message
      lead.update!(etapa_prospect: 'contatado', primeiro_contato_em: Time.current)

      travel(described_class.opening_run_window + 1.second) do
        expect { post_bot_message(content: 'Oi de novo!') }
          .to raise_error(described_class::Blocked) { |e| expect(e.reason).to eq('abertura_ja_enviada') }
      end
      expect(conversation.messages.outgoing.where(sender: agent_bot).count).to eq(1)
    end

    it 'balão seguinte da mesma abertura (split) dentro da janela ainda passa, mesmo antes da confirmação' do
      post_bot_message

      expect(post_bot_message(content: 'Posso te fazer uma pergunta rápida?')).to be_persisted
      expect(lead.reload.etapa_prospect).to eq('backlog')
    end

    it 'opt-out entre dois balões da abertura bloqueia o segundo' do
      post_bot_message
      lead.update!(nao_contatar: true)

      expect { post_bot_message(content: 'segundo balão') }
        .to raise_error(described_class::Blocked) { |e| expect(e.reason).to match(/nao_contatar/) }
    end

    it 'sem ativação válida e sem mensagem do contato, lead em Backlog não recebe abertura' do
      activation.transition!('cancelled', motivo: 'nao_contatar')

      expect_blocked(/primeira_abordagem_sem_autorizacao/)
    end
  end

  describe 'resposta nova' do
    it 'o contato falar antes da abertura invalida a ativação; a mensagem vira conversa' do
      incoming!

      message = post_bot_message(content: 'Oi! Como posso ajudar?')

      expect(message).to be_persisted
      expect(activation.status).to eq('superseded')
    end
  end

  describe 'proteções contra contato proativo (§19.1, §19.2, §28.25, §28.26)' do
    before do
      lead.update!(etapa_prospect: 'em_conversa')
      activation.transition!('consumed', message_id: 1)
    end

    it 'nao_contatar + contato acabou de falar: responde o inbound sem limpar a flag' do
      lead.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar')
      incoming!(at: 1.minute.ago)

      expect(post_bot_message).to be_persisted
      expect(lead.reload.nao_contatar).to be(true)
    end

    it 'nao_contatar + nenhuma mensagem recente do contato: automação proativa (timer/nudge) bloqueada' do
      lead.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar')
      incoming!(at: 2.hours.ago)

      expect_blocked(/contato_proativo_bloqueado:.*nao_contatar/)
    end

    it 'cliente atual: contato proativo bloqueado' do
      lead.update!(relacao_atual: 'cliente_atual')
      incoming!(at: 3.days.ago)

      expect_blocked(/cliente_atual/)
    end

    it 'lead ativo em conversa: nada bloqueia' do
      incoming!(at: 3.hours.ago)

      expect(post_bot_message).to be_persisted
    end
  end

  describe 'atendimento humano (§18.2, §23.2)' do
    before do
      lead.update!(etapa_prospect: 'em_conversa')
      activation.transition!('consumed', message_id: 1)
      incoming!(at: 1.minute.ago)
    end

    it 'humano assumiu: resposta automática bloqueada mesmo com o contato tendo acabado de falar' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: create(:user, account: account).id)

      expect_blocked(/atendimento_humano/)
    end

    describe 'depois de handoff_comercial feito pela própria Lavínia' do
      before do
        OperationalEngine::Tools::HandoffToCommercialService.new(
          account: account, conversation_id: conversation.display_id, motivo_handoff: 'avanco_comercial'
        ).call
      end

      it 'deixa sair a resposta do turno do handoff dentro da janela' do
        expect(post_bot_message(content: 'Vou te passar para o comercial.')).to be_persisted
      end

      it 'bloqueia depois da janela técnica' do
        travel(described_class.handoff_reply_window + 1.second) { expect_blocked(/atendimento_humano/) }
      end

      it 'bloqueia quando um humano já reivindicou a conversa' do
        lead.reload.update!(responsavel_atual_id: create(:user, account: account).id)

        expect_blocked(/atendimento_humano/)
      end

      it 'bloqueia quando um humano já escreveu na conversa depois do handoff' do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                         sender: create(:user, account: account), content: 'Oi, aqui é o Danilo')

        expect_blocked(/atendimento_humano/)
      end
    end

    # CP-16A -- P2-VAL-16 (decisão da Stéphanie em 24/09/2026: responsável Comercial do handoff pedido
    # pela Lavínia = "DANILO", configurado por conta). O responsável vem preenchido PELO handoff e a
    # resposta do próprio turno continua liberada (decisão de 23/09/2026).
    describe 'handoff com responsável Comercial configurado na conta' do
      let(:danilo) { create(:user, account: account) }

      def handoff!
        OperationalEngine::Tools::HandoffToCommercialService.new(
          account: account, conversation_id: conversation.display_id, motivo_handoff: 'avanco_comercial'
        ).call
      end

      before { agent_tenant.update!(commercial_responsible_user_id: danilo.id) }

      it 'grava o Danilo como responsável e ainda deixa sair a resposta do turno do handoff' do
        handoff!

        expect(lead.reload.responsavel_atual_id).to eq(danilo.id)
        expect(post_bot_message(content: 'Vou te passar para o Danilo, do comercial.')).to be_persisted
      end

      it 'bloqueia depois da janela técnica' do
        handoff!

        travel(described_class.handoff_reply_window + 1.second) { expect_blocked(/atendimento_humano/) }
      end

      it 'bloqueia quando um humano já escreveu na conversa depois do handoff' do
        handoff!
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                         sender: danilo, content: 'Oi, aqui é o Danilo')

        expect_blocked(/atendimento_humano/)
      end

      it 'bloqueia quando o responsável foi trocado depois do handoff' do
        handoff!
        lead.reload.update!(responsavel_atual_id: create(:user, account: account).id)

        expect_blocked(/atendimento_humano/)
      end

      it 'bloqueia quando há fato humano de responsável depois do handoff' do
        handoff!
        OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'responsavel_alterado', source: 'human',
                                             metadata: { de: danilo.id, para: danilo.id, motivo: 'assumir' })

        expect_blocked(/atendimento_humano/)
      end

      it 'humano que já era responsável antes do handoff (§18.4) continua bloqueando' do
        OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: danilo.id)
        handoff!

        expect_blocked(/atendimento_humano/)
      end
    end
  end

  it 'falha fechado quando o Engine não responde' do
    allow(OperationalEngine::LeadRepository).to receive(:find_by_telefone).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect_blocked(/engine_indisponivel/)
  end

  it 'contato com telefone e sem lead resolvido: falha fechado (RISK-019-02)' do
    contact.update!(phone_number: '+5511988887777')

    expect_blocked(/lead_nao_resolvido/)
  end

  it 'contato sem telefone (fora do Engine) segue o fluxo nativo' do
    contact.update!(phone_number: nil)

    expect(post_bot_message).to be_persisted
  end

  it 'a janela de resposta padrão é curta (5 min): lembrete/nudge logo depois não passa por "resposta"' do
    expect(described_class.reply_window).to eq(5.minutes)
  end

  # CP-06 -- RISK-026-01 / P2-026-02 (SSOT §18.3 "timers antigos não ressuscitam", §23.2, §28.23):
  # o timer do up2-agents carimba quando nasceu; nascido antes da última mudança de modo não fala.
  describe 'envio programado (carimbo up2_automation)' do
    let(:user) { create(:user, account: account) }

    before do
      conversation.update!(additional_attributes: {})
      lead.update!(etapa_prospect: 'em_conversa')
      incoming!(at: 2.hours.ago)
    end

    def post_scheduled(created_at, kind: 'APPOINTMENT_REMINDER')
      params = { content_attributes: { up2_automation: { kind: kind, job_id: 'job-1', created_at: created_at } } }
      described_class.authorize!(conversation: conversation, params: params) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                         sender: agent_bot, content: 'Oi, conseguiu ver a proposta?')
      end
    end

    it '28.23: timer criado antes do Assumir e disparado durante o atendimento humano é bloqueado' do
      timer_created_at = 1.hour.ago.iso8601
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)

      expect { post_scheduled(timer_created_at) }.to raise_error(described_class::Blocked) { |e| expect(e.reason).to eq('atendimento_humano') }
    end

    it '28.22: timer criado antes do Assumir não ressuscita depois do Devolver' do
      timer_created_at = 1.hour.ago.iso8601
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
      OperationalEngine::TakeoverService.devolver!(lead: lead, user_id: user.id)

      expect { post_scheduled(timer_created_at) }.to raise_error(described_class::Blocked) do |e|
        expect(e.reason).to eq('automacao_anterior_a_mudanca_de_modo')
      end
      expect(conversation.messages.outgoing.where(sender: agent_bot)).to be_empty
    end

    it 'timer novo, nascido depois do Devolver, pode sair' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
      OperationalEngine::TakeoverService.devolver!(lead: lead, user_id: user.id)

      message = travel(1.minute) { post_scheduled(Time.current.iso8601) }

      expect(message).to be_persisted
    end

    it 'aceita content_attributes em JSON (string) e falha fechado com carimbo ilegível' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
      OperationalEngine::TakeoverService.devolver!(lead: lead, user_id: user.id)
      params = { content_attributes: { up2_automation: { kind: 'FOLLOWUP', created_at: 'ontem' } }.to_json }

      expect do
        described_class.authorize!(conversation: conversation, params: params) do
          create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing', sender: agent_bot)
        end
      end.to raise_error(described_class::Blocked) { |e| expect(e.reason).to eq('automacao_anterior_a_mudanca_de_modo') }
    end

    it 'resposta reativa (sem carimbo) depois do Devolver não é afetada' do
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
      OperationalEngine::TakeoverService.devolver!(lead: lead, user_id: user.id)

      expect(post_bot_message).to be_persisted
    end

    # CP-13 (P1-VAL-12): numa conta com Engine, a recovery do SSOT é a única automação de
    # reengajamento -- o follow-up nativo do up2-agents não fala por fora do ciclo do Engine.
    it 'follow-up nativo (FOLLOWUP), redirect e tipo desconhecido são recusados; lembrete de reunião passa' do
      %w[FOLLOWUP REDIRECT_FOLLOWUP REDIRECT_CLOSING QUALQUER_COISA].each do |kind|
        expect { post_scheduled(Time.current.iso8601, kind: kind) }.to raise_error(described_class::Blocked) do |e|
          expect(e.reason).to eq('automacao_fora_do_ciclo_do_engine')
        end
      end
      expect(conversation.messages.outgoing.where(sender: agent_bot)).to be_empty

      expect(post_scheduled(Time.current.iso8601)).to be_persisted
    end

    # CP-16B (P2-VAL-20, decisão da Stéphanie em 24/09/2026): o turno silencioso pós-devolução nunca
    # fala com o lead -- nem se alguém incluir o tipo na lista da ENV.
    it 'post carimbado RESSINCRONIZACAO é sempre recusado, mesmo listado na ENV' do
      with_modified_env(UP_SALES_ENGINE_AUTOMATION_KINDS: 'APPOINTMENT_REMINDER,RESSINCRONIZACAO') do
        expect { post_scheduled(Time.current.iso8601, kind: 'RESSINCRONIZACAO') }.to raise_error(described_class::Blocked) do |e|
          expect(e.reason).to eq('ressincronizacao_nunca_envia')
        end
      end
      expect(conversation.messages.outgoing.where(sender: agent_bot)).to be_empty
    end
  end

  # CP-13 -- P1-VAL-12 (SSOT §15.6-§15.8, 28.4, 28.23, 28.25): post de recovery só com a autorização
  # do Engine e passando de novo pela revalidação completa, no instante do post.
  describe 'recovery (carimbo RECUPERACAO + RecoveryActivation)' do
    let(:zone) { Time.find_zone('America/Sao_Paulo') }
    let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
    let(:inbox) { whatsapp_inbox }
    let(:recovery) { OperationalEngine::RecoveryActivation.write!(conversation, lead, 1, 'whatsapp') }

    after { travel_back }

    # travel_to sem bloco + travel_back: os testes abaixo usam travel_to com bloco (nunca aninhado).
    before do
      travel_to(zone.local(2026, 9, 24, 11, 0))
      conversation.update!(additional_attributes: {})
      lead.update!(etapa_prospect: 'em_conversa', inbox_atual_id: whatsapp_inbox.id, aguardando_resposta: true, recuperacao_status: 'ativa',
                   tentativa_recuperacao: 0, proxima_recuperacao_em: 1.minute.ago, upsales_conversation_atual_id: conversation.id)
      incoming!(at: 1.day.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing', sender: agent_bot,
                       content: 'Quantos quilos por mês?', created_at: 20.hours.ago)
    end

    def post_recovery(job_id: recovery.activation_id, created_at: Time.current.iso8601)
      stamp = { up2_automation: { kind: 'RECUPERACAO', job_id: job_id, created_at: created_at } }
      described_class.authorize!(conversation: conversation, params: { content_attributes: stamp }) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                         sender: agent_bot, content: 'Conseguiu ver o volume?')
      end
    end

    def expect_recovery_blocked(reason_pattern, **args)
      expect { post_recovery(**args) }.to raise_error(described_class::Blocked) { |e| expect(e.reason).to match(reason_pattern) }
    end

    it 'com a ativação autorizada e o lead elegível, sai e consome a ativação; balão da mesma tentativa passa, reenvio não' do
      message = post_recovery

      expect(message).to be_persisted
      expect(OperationalEngine::RecoveryActivation.for(conversation.reload)).to have_attributes(status: 'consumed', message_id: message.id)
      expect(post_recovery).to be_persisted # split humanizado da mesma mensagem
      travel_to(zone.local(2026, 9, 24, 11, 3)) { expect_recovery_blocked(/recuperacao_ja_enviada/) }
    end

    it 'sem ativação, com job_id de outra ativação ou tentativa divergente, não sai' do
      expect_recovery_blocked(/recuperacao_sem_autorizacao/, job_id: SecureRandom.uuid)

      lead.update!(tentativa_recuperacao: 1)
      expect_recovery_blocked(/tentativa_divergente/)
    end

    it 'revalida o §15.8 inteiro no post: humano, não contatar, encerrado, sem aguardar, resposta nova' do
      { { modo_atendimento: 'humano' } => /atendimento_humano/, { nao_contatar: true } => /nao_contatar/,
        { lead_status: 'encerrado' } => /lead_encerrado/, { aguardando_resposta: false } => /nao_aguarda_resposta/ }.each do |change, reason|
        lead.update!(change)
        expect_recovery_blocked(reason)
        lead.update!(modo_atendimento: 'lavinia', nao_contatar: false, lead_status: 'ativo', aguardando_resposta: true)
      end

      incoming!
      expect_recovery_blocked(/resposta_nova/)
      expect(conversation.messages.outgoing.where(content: 'Conseguiu ver o volume?')).to be_empty
    end

    it 'fora da janela de recovery (seg-sex 09-18) não sai' do
      recovery
      travel_to(zone.local(2026, 9, 24, 19, 0)) { expect_recovery_blocked(/fora_da_janela_de_recuperacao/) }
    end

    it '28.22: recovery autorizada antes de uma mudança de modo não sai depois do Devolver' do
      created_at = recovery.authorized_at.iso8601(6)
      user = create(:user, account: account)
      travel_to(zone.local(2026, 9, 24, 11, 1)) do
        OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
        OperationalEngine::TakeoverService.devolver!(lead: lead.reload, user_id: user.id)
      end

      travel_to(zone.local(2026, 9, 24, 11, 2)) { expect_recovery_blocked(/automacao_anterior_a_mudanca_de_modo/, created_at: created_at) }
    end
  end
end
