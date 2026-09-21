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
