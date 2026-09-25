require 'rails_helper'

RSpec.describe OperationalEngine::InboundProcessor do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5513991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def build_message(**overrides)
    create(:message, conversation: conversation, account: account, message_type: 'incoming', **overrides)
  end

  it 'sem telefone no contato, nao faz nada (teste 28.6 nao se aplica)' do
    contact.update!(phone_number: nil)
    message = build_message

    expect { described_class.call(message: message) }.not_to change(OperationalEngine::Lead, :count)
  end

  describe 'lead novo (teste 28.6)' do
    it 'nasce direto em em_conversa, nunca em backlog/contatado' do
      message = build_message

      lead = described_class.call(message: message)

      expect(lead).to be_persisted
      expect(lead.etapa_prospect).to eq('em_conversa')
      expect(lead.entrada_operacao_em).to be_within(1.second).of(message.created_at)
    end

    it 'grava lead_criado, nova_entrada e etapa_alterada' do
      message = build_message

      lead = described_class.call(message: message)

      types = OperationalEngine::LeadEvent.where(lead: lead).pluck(:event_type)
      expect(types).to contain_exactly('lead_criado', 'nova_entrada', 'etapa_alterada')
    end

    it 'usa inbound_direto como origem e marca a inbox de entrada e atual' do
      message = build_message

      lead = described_class.call(message: message)

      expect(lead.origem_lead).to eq('inbound_direto')
      expect(lead.inbox_entrada_id).to eq(conversation.inbox_id)
      expect(lead.inbox_atual_id).to eq(conversation.inbox_id)
    end

    it 'nao duplica lead pro mesmo telefone processado duas vezes (teste 28.9 aplicado ao inbound)' do
      message = build_message

      described_class.call(message: message)

      expect { described_class.call(message: message) }.not_to change(OperationalEngine::Lead, :count)
    end

    it 'cria a projecao Sales::Lead' do
      message = build_message

      described_class.call(message: message)

      expect(Sales::Lead.find_by(account_id: account.id, contact_id: contact.id)).to be_present
    end
  end

  describe 'lead existente (teste 28.8)' do
    # etapa explícita: a etapa padrão do lead é backlog, e desde o CP-16A (P2-VAL-15) um lead em
    # Backlog que fala vira inbound -- caso próprio, coberto no describe do P2-VAL-15 abaixo.
    let!(:lead) do
      OperationalEngine::LeadRepository.find_or_create_by_telefone(
        conta_id: account.id, telefone: contact.phone_number,
        attributes: { origem_lead: 'google_ads', inbox_entrada_id: 999, inbox_atual_id: 999, upsales_contact_id: contact.id,
                      etapa_prospect: 'em_conversa', etapa_entrou_em: 1.day.ago }
      )
    end

    it 'nao cria um segundo lead' do
      message = build_message

      expect { described_class.call(message: message) }.not_to change(OperationalEngine::Lead, :count)
    end

    it 'preserva origem_lead original mesmo mensagem chegando por outra inbox' do
      message = build_message

      described_class.call(message: message)

      expect(lead.reload.origem_lead).to eq('google_ads')
    end

    it 'atualiza inbox_atual_id quando a mensagem chega por uma inbox diferente, e registra nova_entrada' do
      message = build_message

      described_class.call(message: message)

      expect(lead.reload.inbox_atual_id).to eq(conversation.inbox_id)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'nova_entrada').count).to eq(1)
    end

    it 'na mesma inbox de sempre, atualiza ultima_interacao_em e registra a resposta do lead' do
      lead.update!(inbox_atual_id: conversation.inbox_id)
      message = build_message

      expect { described_class.call(message: message) }.to change(OperationalEngine::LeadEvent, :count).by(1)
      expect(lead.reload.ultima_interacao_em).to be_within(1.second).of(message.created_at)
      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'lead_respondeu').sole.external_id).to eq(message.id.to_s)
    end

    it 'reprocessa a mesma mensagem sem duplicar o evento de resposta' do
      lead.update!(inbox_atual_id: conversation.inbox_id)
      message = build_message

      2.times { described_class.call(message: message) }

      expect(OperationalEngine::LeadEvent.where(lead: lead, event_type: 'lead_respondeu').count).to eq(1)
    end

    it 'tambem sincroniza o card Comercial (Fase 9) quando o lead ja e uma oportunidade' do
      lead.update!(etapa_comercial: 'oportunidade')
      message = build_message

      described_class.call(message: message)

      comercial_card = Sales::Lead.joins(:pipeline).find_by(contact_id: contact.id, sales_pipelines: { engine_kind: 'comercial' })
      expect(comercial_card).to be_present
    end
  end

  # CP-01 (§23.2, resposta nova): o contato falou antes da abertura do Dispatcher sair.
  describe 'abertura outbound ainda pendente na conversa' do
    let!(:lead) { OperationalEngine::Lead.create!(conta_id: account.id, telefone: contact.phone_number, etapa_prospect: 'backlog') }

    it 'invalida a ativação (superseded) com o id da mensagem do contato' do
      conversation.update!(additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
      message = build_message

      described_class.call(message: message)

      activation = OperationalEngine::OriginationActivation.for(conversation.reload)
      expect(activation.status).to eq('superseded')
      expect(conversation.additional_attributes.dig('up_sales_origination', 'message_id')).to eq(message.id)
    end

    it 'não mexe numa ativação já consumida' do
      conversation.update!(additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))
      OperationalEngine::OriginationActivation.for(conversation).transition!('consumed', message_id: 1)

      described_class.call(message: build_message)

      expect(OperationalEngine::OriginationActivation.for(conversation.reload).status).to eq('consumed')
    end
  end

  # CP-08 -- P1-VAL-01 (SSOT §11.3, testes 28.3 e 28.9).
  describe 'outbound que responde (teste 28.3)' do
    let!(:lead) do
      OperationalEngine::Lead.create!(
        conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id, modo_entrada: 'outbound',
        inbox_atual_id: conversation.inbox_id, etapa_prospect: 'contatado', etapa_entrou_em: 1.day.ago,
        entrada_operacao_em: 1.day.ago, primeiro_contato_em: 1.day.ago,
        recuperacao_status: 'ativa', proxima_recuperacao_em: 1.day.from_now
      )
    end

    def events(type)
      OperationalEngine::LeadEvent.where(lead: lead, event_type: type)
    end

    it 'vai de Contatado para Em conversa, preenche primeira_resposta_em e cancela a recovery' do
      message = build_message

      described_class.call(message: message)

      lead.reload
      expect(lead.etapa_prospect).to eq('em_conversa')
      expect(lead.etapa_entrou_em).to be_within(1.second).of(message.created_at)
      expect(lead.primeira_resposta_em).to be_within(1.second).of(message.created_at)
      expect(lead.ultima_interacao_em).to be_within(1.second).of(message.created_at)
      expect(lead.recuperacao_status).to eq('inativa')
      expect(lead.proxima_recuperacao_em).to be_nil
    end

    it 'grava lead_respondeu, etapa_alterada (contatado -> em_conversa) e recuperacao_respondida' do
      described_class.call(message: build_message)

      expect(events('lead_respondeu').count).to eq(1)
      expect(events('etapa_alterada').sole.metadata).to include('de' => 'contatado', 'para' => 'em_conversa', 'motivo' => 'lead_respondeu')
      expect(events('recuperacao_respondida').count).to eq(1)
    end

    it 'webhook duplicado (28.9): o mesmo message_id processado duas vezes gera uma única transição' do
      message = build_message

      2.times { described_class.call(message: message) }

      expect(events('lead_respondeu').count).to eq(1)
      expect(events('etapa_alterada').count).to eq(1)
    end

    it 'não sobrescreve primeira_resposta_em já preenchida e não gera recuperacao_respondida sem recovery ativa' do
      original = 3.days.ago.change(usec: 0)
      lead.update!(primeira_resposta_em: original, recuperacao_status: 'inativa', proxima_recuperacao_em: nil)

      described_class.call(message: build_message)

      expect(lead.reload.primeira_resposta_em).to eq(original)
      expect(events('recuperacao_respondida')).to be_empty
    end

    it 'segunda mensagem do lead já em conversa não repete a transição' do
      described_class.call(message: build_message)
      described_class.call(message: build_message)

      expect(events('lead_respondeu').count).to eq(2)
      expect(lead.reload.etapa_prospect).to eq('em_conversa')
    end

    it 'leva o card Prospect para Em conversa' do
      described_class.call(message: build_message)

      card = Sales::Lead.joins(:pipeline).find_by(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'prospect' })
      expect(card&.stage&.engine_stage_key).to eq('em_conversa')
    end

    it 'falha na projeção não derruba o inbound: o fato fica no Engine e a projeção fica pendente' do
      allow(OperationalEngine::SalesProjectionSync).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'CRM fora')

      expect { described_class.call(message: build_message) }.not_to raise_error

      expect(lead.reload.etapa_prospect).to eq('em_conversa')
      expect(OperationalEngine::ProjectionRequest.find(lead.lead_id)).to be_status_pendente
    end
  end

  # CP-16A -- P2-VAL-15 (decisão da Stéphanie em 24/09/2026: lead em Backlog que fala antes da
  # abertura = inbound, "SIM"; SSOT §11.2 aplicado ao lead existente, §5.4 origem write-once).
  describe 'lead em Backlog que manda mensagem antes da abertura (P2-VAL-15)' do
    let!(:lead) do
      OperationalEngine::Lead.create!(
        conta_id: account.id, telefone: contact.phone_number, upsales_contact_id: contact.id, origem_lead: 'lista_fria',
        modo_entrada: 'outbound', tipo_entrada: 'novo', etapa_prospect: 'backlog', etapa_entrou_em: 2.days.ago
      )
    end

    def events(type)
      OperationalEngine::LeadEvent.where(lead: lead, event_type: type)
    end

    it 'vira inbound em Em conversa com entrada_operacao_em e etapa_entrou_em no horário da mensagem' do
      message = build_message

      described_class.call(message: message)

      lead.reload
      expect(lead.modo_entrada).to eq('inbound')
      expect(lead.etapa_prospect).to eq('em_conversa')
      expect(lead.entrada_operacao_em).to be_within(1.second).of(message.created_at)
      expect(lead.etapa_entrou_em).to be_within(1.second).of(message.created_at)
      expect(lead.inbox_entrada_id).to eq(conversation.inbox_id)
    end

    it 'preserva origem_lead (write-once, §5.4) e não recria o lead' do
      expect { described_class.call(message: build_message) }.not_to change(OperationalEngine::Lead, :count)

      expect(lead.reload.origem_lead).to eq('lista_fria')
      expect(events('lead_criado')).to be_empty
    end

    it 'grava nova_entrada e etapa_alterada backlog -> em_conversa com motivo explícito' do
      described_class.call(message: build_message)

      expect(events('nova_entrada').sole.metadata).to include('modo_entrada' => 'inbound', 'motivo' => 'lead_iniciou_antes_da_abertura')
      expect(events('etapa_alterada').sole.metadata).to include('de' => 'backlog', 'para' => 'em_conversa',
                                                                'motivo' => 'lead_iniciou_antes_da_abertura')
    end

    it 'não sobrescreve entrada_operacao_em já preenchida (write-once)' do
      original = 3.days.ago.change(usec: 0)
      lead.update!(entrada_operacao_em: original)

      described_class.call(message: build_message)

      expect(lead.reload.entrada_operacao_em).to eq(original)
      expect(lead.etapa_prospect).to eq('em_conversa')
    end

    it 'webhook duplicado: o mesmo message_id processado duas vezes gera uma única transição' do
      message = build_message

      2.times { described_class.call(message: message) }

      expect(events('etapa_alterada').count).to eq(1)
      expect(events('nova_entrada').count).to eq(1)
    end

    it 'supersede a ativação pendente e sai da fila do Dispatcher' do
      conversation.update!(additional_attributes: OperationalEngine::OriginationActivation.build_attributes(lead))

      described_class.call(message: build_message)

      expect(OperationalEngine::OriginationActivation.for(conversation.reload).status).to eq('superseded')
      expect(OperationalEngine::BacklogSelector.candidatos(conta_id: account.id)).not_to include(lead.reload)
      expect(OperationalEngine::OutboundEligibility.origination_blockers(lead)).to include('fora_do_backlog')
    end

    it 'entra no Dashboard Prospect como inbound (CP-11)' do
      described_class.call(message: build_message)

      filtros = { data_inicial: 1.day.ago.to_date.iso8601, data_final: 1.day.from_now.to_date.iso8601 }
      inbound = OperationalEngine::ProspectDashboardMetrics.call(conta_id: account.id, filtros: filtros.merge(modo: 'inbound'))
      outbound = OperationalEngine::ProspectDashboardMetrics.call(conta_id: account.id, filtros: filtros.merge(modo: 'outbound'))
      expect(inbound[:big_numbers][:leads_iniciados]).to eq(1)
      expect(inbound[:big_numbers][:em_conversa][:absoluto]).to eq(1)
      expect(outbound[:big_numbers][:leads_iniciados]).to eq(0)
    end

    it 'leva o card Prospect para Em conversa' do
      described_class.call(message: build_message)

      card = Sales::Lead.joins(:pipeline).find_by(operational_lead_id: lead.lead_id, sales_pipelines: { engine_kind: 'prospect' })
      expect(card&.stage&.engine_stage_key).to eq('em_conversa')
    end

    it 'lead de Backlog já encerrado (ex.: cliente atual) não entra na operação Prospect' do
      lead.update!(lead_status: 'encerrado', motivo_encerramento: 'cliente_atual', relacao_atual: 'cliente_atual')

      described_class.call(message: build_message)

      expect(lead.reload.etapa_prospect).to eq('backlog')
      expect(lead.modo_entrada).to eq('outbound')
      expect(lead.entrada_operacao_em).to be_nil
    end
  end
end
