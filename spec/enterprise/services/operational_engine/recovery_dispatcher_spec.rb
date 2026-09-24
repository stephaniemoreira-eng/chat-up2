require 'rails_helper'

# CP-13 -- P1-VAL-12 (SSOT §15, §7.4, §19, §23; testes 28.4, 28.5, 28.23, 28.25, 28.40): o ciclo de
# Recovery de ponta a ponta -- nascimento na confirmação real do envio, fila por inbox com o
# dispatcher, post autorizado pelo OutboundSendGate, confirmação real (source_id) incrementando a
# tentativa, e-mail/pulo, esgotamento e cancelamento por resposta.
RSpec.describe OperationalEngine::RecoveryDispatcher do
  let(:zone) { Time.find_zone('America/Sao_Paulo') }
  let(:account) { create(:account, name: 'Lava e Pronto') }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let!(:agent_tenant) { create(:up_sales_agent_tenant, account: account, whatsapp_inbox: inbox) }
  let(:agent_bot) { create(:agent_bot) }
  let(:recover_url) { 'https://agents.up2aceleradora.com.br/api/v1/chatwoot/recover' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before { create(:up_sales_agent_slot, account: account, up2_agents_agent_id: '77') }

  def sp(*args)
    zone.local(*args)
  end

  def tick(at)
    travel_to(at) { described_class.call(conta_id: account.id) }
  end

  def conversation_for(phone)
    contact = create(:contact, account: account, phone_number: phone)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def build_lead(phone, **attributes)
    defaults = { conta_id: account.id, telefone: phone, etapa_entrou_em: 2.days.ago, modo_entrada: 'outbound' }
    OperationalEngine::Lead.create!(defaults.merge(attributes))
  end

  def confirm!(message)
    message.update!(source_id: "wamid.#{message.id}")
    OperationalEngine::ConfirmOutboundSendService.call(message: message)
    message
  end

  # A Lavínia fala (o commit do turno já gravou aguardando_resposta/ultimo_ponto -- CP-03) e o provedor
  # confirma o envio real.
  def lavinia_says!(lead, conversation, at:, aguardando: true, ultimo_ponto: nil)
    travel_to(at) do
      lead.reload.update!(aguardando_resposta: aguardando, **(ultimo_ponto ? { ultimo_ponto: ultimo_ponto } : {}))
      confirm!(create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing',
                                sender: agent_bot, content: 'Hoje vocês lavam o enxoval internamente?'))
    end
  end

  def lead_replies!(conversation, at:)
    travel_to(at) do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming',
                                 sender: conversation.contact, content: 'Oi, desculpa a demora')
      OperationalEngine::InboundProcessor.call(message: message)
    end
  end

  # Simula o up2-agents: a Lavínia gera a recovery e posta pelo mesmo caminho do post real
  # (OutboundSendGate), com o carimbo da ativação. `confirm: false` = o provedor ainda não confirmou.
  def stub_recover(before_post: nil, confirm: true)
    stub_request(:post, recover_url).to_return do |request|
      body = JSON.parse(request.body)
      before_post&.call
      post_recovery(body, confirm)
    end
  end

  def post_recovery(body, confirm)
    conversation = Conversation.find_by!(account_id: account.id, display_id: body['chatwootConversationId'])
    stamp = { 'up2_automation' => { 'kind' => 'RECUPERACAO', 'job_id' => body['recoveryActivationId'], 'created_at' => body['authorizedAt'] } }
    message = OperationalEngine::OutboundSendGate.authorize!(conversation: conversation, params: { content_attributes: stamp }) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing', sender: agent_bot,
                       content: 'Conseguiu pensar sobre o volume?', content_attributes: stamp)
    end
    confirm!(message) if confirm
    { status: 200, body: { ok: true, outcome: 'posted' }.to_json, headers: json }
  rescue OperationalEngine::OutboundSendGate::Blocked => e
    { status: 200, body: { ok: false, outcome: 'blocked', reason: e.reason }.to_json, headers: json }
  end

  def recover_calls
    a_request(:post, recover_url)
  end

  def events(lead, type)
    OperationalEngine::LeadEvent.where(lead_id: lead.lead_id, event_type: type)
  end

  def cycle(lead)
    lead.reload.slice('recuperacao_status', 'tentativa_recuperacao', 'proxima_recuperacao_em', 'lead_status', 'motivo_encerramento').symbolize_keys
  end

  describe '28.4 -- outbound nunca responde' do
    let(:conversation) { conversation_for('+5513991230001') }
    let!(:lead) { build_lead('+5513991230001', etapa_prospect: 'backlog') }

    # Quinta 24/09 10:00: a abertura é confirmada -> Contatado e timer da tentativa 1 (+1 dia útil).
    before { lavinia_says!(lead, conversation, at: sp(2026, 9, 24, 10, 0), ultimo_ponto: 'primeira_abordagem') }

    it 'o envio confirmado da abertura arma o timer (não é "precisou de recovery" ainda)' do
      expect(lead.reload.etapa_prospect).to eq('contatado')
      expect(cycle(lead)).to include(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: sp(2026, 9, 25, 10, 0))
      expect(lead.upsales_conversation_atual_id).to eq(conversation.id)
      expect(OperationalEngine::LeadEvent.where(lead_id: lead.lead_id).where('event_type LIKE ?', 'recuperacao%')).to be_empty
    end

    it 'aplica a cadência +1/+3 dias úteis no WhatsApp e, sem e-mail, pula a tentativa 3 e encerra por sem_resposta' do
      stub_recover

      tick(sp(2026, 9, 25, 9, 55)) # ainda não venceu
      expect(recover_calls).not_to have_been_made

      tick(sp(2026, 9, 25, 10, 0))
      expect(cycle(lead)).to include(recuperacao_status: 'ativa', tentativa_recuperacao: 1, proxima_recuperacao_em: sp(2026, 9, 30, 10, 0))

      tick(sp(2026, 9, 30, 10, 0))
      expect(cycle(lead)).to include(tentativa_recuperacao: 2, proxima_recuperacao_em: sp(2026, 10, 7, 10, 0))

      tick(sp(2026, 10, 7, 10, 0))
      expect(cycle(lead)).to include(recuperacao_status: 'inativa', lead_status: 'encerrado', motivo_encerramento: 'sem_resposta')
      expect(recover_calls).to have_been_made.twice
    end

    it 'grava os eventos canônicos do §7.4 com tentativa, canal, ultimo_ponto e IDs externos' do
      stub_recover
      [sp(2026, 9, 25, 10, 0), sp(2026, 9, 30, 10, 0), sp(2026, 10, 7, 10, 0)].each { |at| tick(at) }

      expect(events(lead, 'recuperacao_iniciada').sole.metadata).to include('cadencia' => 'nunca_respondeu', 'ultimo_ponto' => 'primeira_abordagem',
                                                                            'inbox_id' => inbox.id, 'conversation_id' => conversation.id)
      enviadas = events(lead, 'recuperacao_mensagem_enviada').order(:event_at).map(&:metadata)
      expect(enviadas.pluck('tentativa', 'canal')).to eq([[1, 'whatsapp'], [2, 'whatsapp']])
      expect(enviadas.first.keys).to include('message_id', 'source_id', 'activation_id', 'inbox_id')
      expect(events(lead, 'recuperacao_esgotada').sole.metadata).to include('tentativa_pulada' => 3, 'motivo_pulo' => 'email_indisponivel')
      expect(events(lead, 'lead_encerrado').sole.metadata).to include('de' => 'ativo', 'para' => 'encerrado', 'motivo' => 'sem_resposta')
    end

    # O canal de e-mail depende do método de entrega real: sem SMTP_ADDRESS o Rails cai em :sendmail
    # (tratado como canal indisponível). Os dois cenários ficam explícitos aqui.
    describe 'tentativa 3 por e-mail' do
      around do |example|
        original = ActionMailer::Base.delivery_method
        example.run
      ensure
        ActionMailer::Base.delivery_method = original
      end

      before do
        stub_recover
        lead.reload.update!(email: 'compras@hotel.example.com')
        [sp(2026, 9, 25, 10, 0), sp(2026, 9, 30, 10, 0)].each { |at| tick(at) }
      end

      it 'com e-mail e canal configurado, a tentativa 3 sai por e-mail e o ciclo esgota em seguida' do
        ActionMailer::Base.delivery_method = :test

        expect { tick(sp(2026, 10, 7, 10, 0)) }.to change(ActionMailer::Base.deliveries, :count).by(1)
        expect(ActionMailer::Base.deliveries.last.to).to eq(['compras@hotel.example.com'])
        expect(events(lead, 'recuperacao_email_enviado').sole.metadata).to include('tentativa' => 3, 'canal' => 'email')
        expect(cycle(lead)).to include(tentativa_recuperacao: 3, lead_status: 'ativo')

        tick(sp(2026, 10, 7, 10, 5))
        expect(cycle(lead)).to include(lead_status: 'encerrado', motivo_encerramento: 'sem_resposta')
        expect(events(lead, 'recuperacao_esgotada').sole.metadata).to include('tentativas' => 3)
      end

      it 'com e-mail mas sem canal real (sendmail, sem SMTP), pula a ação sem fingir envio e esgota' do
        ActionMailer::Base.delivery_method = :sendmail

        expect { tick(sp(2026, 10, 7, 10, 0)) }.not_to change(ActionMailer::Base.deliveries, :count)
        expect(events(lead, 'recuperacao_email_enviado')).to be_empty
        expect(events(lead, 'recuperacao_esgotada').sole.metadata).to include('motivo_pulo' => 'canal_email_nao_configurado')
        expect(cycle(lead)).to include(lead_status: 'encerrado', motivo_encerramento: 'sem_resposta')
      end
    end

    it 'a resposta do lead zera e cancela as tentativas futuras (§15.9)' do
      stub_recover
      tick(sp(2026, 9, 25, 10, 0))

      lead_replies!(conversation, at: sp(2026, 9, 25, 15, 0))
      expect(cycle(lead)).to include(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: nil)
      expect(events(lead, 'recuperacao_respondida').sole.metadata).to include('tentativa' => 1)

      tick(sp(2026, 9, 30, 10, 0))
      expect(recover_calls).to have_been_made.once
    end

    it 'respeita a janela: vencido no fim de semana ou à noite não sai' do
      stub_recover
      lead.reload.update!(proxima_recuperacao_em: sp(2026, 9, 25, 10, 0))

      [sp(2026, 9, 26, 11, 0), sp(2026, 9, 28, 18, 0), sp(2026, 9, 28, 8, 59)].each { |at| tick(at) }
      expect(recover_calls).not_to have_been_made

      tick(sp(2026, 9, 28, 9, 0))
      expect(recover_calls).to have_been_made.once
    end
  end

  describe '28.5 -- conversa iniciada e interrompida' do
    let(:conversation) { conversation_for('+5513991230002') }
    let!(:lead) { build_lead('+5513991230002', etapa_prospect: 'em_conversa', modo_entrada: 'inbound', inbox_atual_id: inbox.id) }

    before do
      travel_to(sp(2026, 9, 24, 16, 50)) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
      end
      lavinia_says!(lead, conversation, at: sp(2026, 9, 24, 17, 0), ultimo_ponto: 'aguardando_volume')
    end

    it 'usa a cadência "já conversava": +2h fora da janela carrega para a próxima janela útil' do
      expect(cycle(lead)).to include(proxima_recuperacao_em: sp(2026, 9, 25, 9, 0))
    end

    it 'mantém o ultimo_ponto no ciclo e agenda a tentativa 2 a +1 dia útil do envio confirmado' do
      stub_recover

      tick(sp(2026, 9, 25, 9, 0))

      expect(lead.reload.ultimo_ponto).to eq('aguardando_volume')
      expect(events(lead, 'recuperacao_iniciada').sole.metadata).to include('cadencia' => 'conversava', 'ultimo_ponto' => 'aguardando_volume')
      expect(cycle(lead)).to include(tentativa_recuperacao: 1, proxima_recuperacao_em: sp(2026, 9, 28, 9, 0))
      expect(recover_calls.with(body: hash_including('tentativa' => 1))).to have_been_made.once
    end

    it 'parar de novo depois de responder inicia um ciclo novo na tentativa 1' do
      stub_recover
      tick(sp(2026, 9, 25, 9, 0))
      lead_replies!(conversation, at: sp(2026, 9, 25, 10, 0))

      lavinia_says!(lead, conversation, at: sp(2026, 9, 25, 10, 1), ultimo_ponto: 'aguardando_frequencia')

      expect(cycle(lead)).to include(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: sp(2026, 9, 25, 12, 1))
    end

    it 'a Lavínia sem aguardar resposta não arma nada (§15.2)' do
      lead.reload.update!(proxima_recuperacao_em: nil)
      lavinia_says!(lead, conversation, at: sp(2026, 9, 25, 10, 0), aguardando: false)

      expect(cycle(lead)).to include(proxima_recuperacao_em: nil)
    end
  end

  describe 'proteções (28.23, 28.25, §15.8)' do
    let(:conversation) { conversation_for('+5513991230003') }
    let!(:lead) { build_lead('+5513991230003', etapa_prospect: 'em_conversa', inbox_atual_id: inbox.id) }
    let(:user) { create(:user, account: account) }

    before { lavinia_says!(lead, conversation, at: sp(2026, 9, 24, 10, 0), ultimo_ponto: 'aguardando_volume') }

    def outgoing_recoveries
      conversation.messages.outgoing.where(sender: agent_bot).where('content LIKE ?', 'Conseguiu%')
    end

    it '28.23: humano assume enquanto a recovery é gerada -- a revalidação no post bloqueia e nada incrementa' do
      assumir = -> { OperationalEngine::TakeoverService.assumir!(lead: OperationalEngine::Lead.find(lead.lead_id), user_id: user.id) }
      stub_recover(before_post: assumir)

      tick(sp(2026, 9, 24, 12, 0))

      expect(outgoing_recoveries).to be_empty
      expect(cycle(lead)).to include(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: nil)
      expect(OperationalEngine::RecoveryActivation.for(conversation.reload).status).to eq('cancelled')
    end

    it '28.25: não contatar ativado enquanto a recovery é gerada -- nada sai' do
      stub_recover(before_post: -> { OperationalEngine::Lead.find(lead.lead_id).update!(nao_contatar: true) })

      tick(sp(2026, 9, 24, 12, 0))

      expect(outgoing_recoveries).to be_empty
      expect(lead.reload.tentativa_recuperacao).to eq(0)
    end

    it 'timer vencido de lead que já não pode receber recovery é interrompido sem chamar a Lavínia' do
      stub_recover
      lead.reload.update!(nao_contatar: true, lead_status: 'encerrado', motivo_encerramento: 'nao_contatar')

      tick(sp(2026, 9, 24, 12, 0))

      expect(recover_calls).not_to have_been_made
      expect(cycle(lead)).to include(proxima_recuperacao_em: nil)
      expect(events(lead, 'recuperacao_interrompida').sole.metadata['motivos']).to include('nao_contatar', 'lead_encerrado')
    end

    it '28.22: Assumir e Devolver não ressuscitam o timer antigo' do
      stub_recover
      OperationalEngine::TakeoverService.assumir!(lead: lead, user_id: user.id)
      OperationalEngine::TakeoverService.devolver!(lead: lead.reload, user_id: user.id)

      tick(sp(2026, 9, 24, 12, 0))

      expect(recover_calls).not_to have_been_made
      expect(cycle(lead)).to include(proxima_recuperacao_em: nil)
    end
  end

  describe 'tentativa só incrementa com envio confirmado (§15.8, §23.3)' do
    let(:conversation) { conversation_for('+5513991230004') }
    let!(:lead) { build_lead('+5513991230004', etapa_prospect: 'em_conversa', inbox_atual_id: inbox.id) }

    before { lavinia_says!(lead, conversation, at: sp(2026, 9, 24, 10, 0)) }

    it 'post gravado sem confirmação do provedor não incrementa nem é reenviado; a confirmação tardia incrementa uma vez' do
      stub_recover(confirm: false)

      tick(sp(2026, 9, 24, 12, 0))
      tick(sp(2026, 9, 24, 12, 30))
      expect(cycle(lead)).to include(recuperacao_status: 'ativa', tentativa_recuperacao: 0)
      expect(recover_calls).to have_been_made.once

      message = conversation.messages.outgoing.order(:id).last
      2.times { travel_to(sp(2026, 9, 24, 12, 40)) { confirm!(message) } }
      expect(cycle(lead)).to include(tentativa_recuperacao: 1)
      expect(events(lead, 'recuperacao_mensagem_enviada').count).to eq(1)
    end

    it 'falha técnica: não incrementa, registra a falha e, depois de 3 execuções, interrompe o ciclo visivelmente' do
      stub_request(:post, recover_url).to_return(status: 500, body: { error: 'up2-agents fora do ar' }.to_json, headers: json)

      [sp(2026, 9, 24, 12, 0), sp(2026, 9, 24, 12, 15), sp(2026, 9, 24, 12, 30), sp(2026, 9, 24, 12, 45)].each { |at| tick(at) }

      expect(recover_calls).to have_been_made.times(3)
      expect(events(lead, 'recuperacao_envio_falhou').order(:event_at).map { |event| event.metadata['terminal'] }).to eq([false, false, true])
      expect(cycle(lead)).to include(recuperacao_status: 'inativa', tentativa_recuperacao: 0, proxima_recuperacao_em: nil)
      expect(events(lead, 'recuperacao_interrompida').sole.metadata['motivos']).to eq(['falha_tecnica_persistente'])
    end
  end

  describe 'fila única por inbox (§15.6, §15.7)' do
    let(:conversation_nunca) { conversation_for('+5513991230005') }
    let(:conversation_conversava) { conversation_for('+5513991230006') }
    let!(:nunca) { build_lead('+5513991230005', etapa_prospect: 'contatado', primeiro_contato_em: 3.days.ago) }
    let!(:conversava) { build_lead('+5513991230006', etapa_prospect: 'em_conversa', inbox_atual_id: inbox.id) }

    before do
      lavinia_says!(nunca, conversation_nunca, at: sp(2026, 9, 23, 10, 0))       # vence qui 24/09 10:00
      lavinia_says!(conversava, conversation_conversava, at: sp(2026, 9, 24, 9, 0)) # vence qui 24/09 11:00
      stub_recover
    end

    it 'prioriza quem conversava e parou, não dispara em rajada e preserva o outro para o próximo intervalo' do
      tick(sp(2026, 9, 24, 11, 0))
      expect(recover_calls.with(body: hash_including('chatwootConversationId' => conversation_conversava.display_id))).to have_been_made.once
      expect(recover_calls).to have_been_made.once

      tick(sp(2026, 9, 24, 11, 2)) # dentro do intervalo da inbox: nada sai
      expect(recover_calls).to have_been_made.once

      tick(sp(2026, 9, 24, 11, 6))
      expect(recover_calls.with(body: hash_including('chatwootConversationId' => conversation_nunca.display_id))).to have_been_made.once
    end

    it 'recovery não consome o limite de 20 novas ativações (e sai mesmo com o limite esgotado)' do
      travel_to(sp(2026, 9, 24, 10, 30)) do
        20.times { |i| build_lead("+55139912400#{format('%02d', i)}", etapa_prospect: 'contatado', primeiro_contato_em: Time.current) }
      end

      ativados = -> { OperationalEngine::Lead.where(conta_id: account.id).where.not(primeiro_contato_em: nil).count }
      travel_to(sp(2026, 9, 24, 10, 40)) { expect(OperationalEngine::BacklogCapacity.disponivel(conta_id: account.id)).to eq(0) }

      expect { tick(sp(2026, 9, 24, 10, 40)) }.not_to(change { ativados.call })
      expect(recover_calls).to have_been_made.once
      travel_to(sp(2026, 9, 24, 10, 41)) { expect(OperationalEngine::BacklogCapacity.disponivel(conta_id: account.id)).to eq(0) }
    end
  end
end
