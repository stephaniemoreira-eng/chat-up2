require 'rails_helper'

# CP-06 -- P1-026-01 / RISK-026-01 (SSOT §4, §18.2, §18.3): modo_atendimento projetado na conversa
# do canal -- é por ela que o up2-agents decide se a Lavínia atende (status pending, sem humano).
RSpec.describe OperationalEngine::ConversationModeProjection do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991230001') }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    create(:agent_bot_inbox, inbox: inbox)
    create(:inbox_member, user: user, inbox: inbox)
  end

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id,
      upsales_conversation_atual_id: conversation.id
    }.merge(overrides))
  end

  it 'humano com responsável: conversa pending vira open (a Lavínia deixa de atender)' do
    conversation.update!(status: :pending)

    described_class.call(build_lead(modo_atendimento: 'humano', responsavel_atual_id: user.id))

    expect(conversation.reload).to be_open
  end

  it 'lavinia: conversa open com humano atribuído volta a pending e sem responsável' do
    conversation.update!(status: :open, assignee: user)

    described_class.call(build_lead(modo_atendimento: 'lavinia'))

    expect(conversation.reload).to be_pending
    expect(conversation.assignee_id).to be_nil
  end

  it 'humano sem responsável (handoff com responsável Comercial pendente) não toca a conversa' do
    conversation.update!(status: :pending)

    described_class.call(build_lead(modo_atendimento: 'humano', responsavel_atual_id: nil, motivo_handoff: 'avanco_comercial'))

    expect(conversation.reload).to be_pending
  end

  it 'nunca reabre conversa resolvida nem toca inbox sem bot ativo' do
    conversation.update!(status: :resolved)
    described_class.call(build_lead(modo_atendimento: 'lavinia'))
    expect(conversation.reload).to be_resolved

    AgentBotInbox.where(inbox: inbox).delete_all
    conversation.update!(status: :open)
    described_class.call(OperationalEngine::Lead.find_by!(upsales_conversation_atual_id: conversation.id))
    expect(conversation.reload).to be_open
  end

  it 'é idempotente e ignora lead sem conversa' do
    conversation.update!(status: :pending)
    lead = build_lead(modo_atendimento: 'lavinia')

    expect { 2.times { described_class.call(lead) } }.not_to(change { conversation.reload.updated_at })
    orphan = build_lead(telefone: '+5513991230002', upsales_contact_id: nil, upsales_conversation_atual_id: nil)
    expect { described_class.call(orphan) }.not_to raise_error
  end

  # CP-16A -- P2-VAL-16 (decisão da Stéphanie em 24/09/2026: responsável Comercial do handoff = Danilo,
  # configurado por conta). Responsável gravado PELO handoff: a conversa só abre depois da resposta do
  # turno do handoff (janela OperationalEngine::HandoffReplyWindow).
  describe 'responsável gravado pelo próprio handoff (P2-VAL-16)' do
    def handoff_lead
      build_lead(modo_atendimento: 'humano', responsavel_atual_id: user.id, motivo_handoff: 'avanco_comercial').tap do |lead|
        OperationalEngine::LeadEvent.create!(lead: lead, event_type: 'handoff_comercial', source: 'lavinia',
                                             metadata: { transicoes: { responsavel_atual_id: { de: nil, para: user.id } } })
      end
    end

    before { conversation.update!(status: :pending) }

    it 'dentro da janela não abre a conversa e agenda a reprojeção para depois dela' do
      lead = handoff_lead

      expect { described_class.call(lead) }.to have_enqueued_job(OperationalEngine::ConversationModeProjectionJob).with(lead.lead_id)
      expect(conversation.reload).to be_pending
    end

    it 'depois da janela a reprojeção abre a conversa' do
      lead = handoff_lead

      travel(OperationalEngine::HandoffReplyWindow.duration + 5.seconds) do
        OperationalEngine::ConversationModeProjectionJob.perform_now(lead.lead_id)
      end

      expect(conversation.reload).to be_open
    end

    it 'humano escreveu na conversa depois do handoff: abre na hora' do
      lead = handoff_lead
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing', sender: user, content: 'Oi')
      conversation.update!(status: :pending)

      described_class.call(lead)

      expect(conversation.reload).to be_open
    end

    it 'responsável diferente do gravado pelo handoff (humano assumiu depois): abre na hora' do
      lead = handoff_lead
      lead.update!(responsavel_atual_id: create(:user, account: account).id)

      described_class.call(lead)

      expect(conversation.reload).to be_open
    end
  end
end
