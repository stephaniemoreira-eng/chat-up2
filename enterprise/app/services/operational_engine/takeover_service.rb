# Assumir/Devolver do §18.2/18.3 e testes 28.19-28.23. A garantia de "humano não é atropelado"
# não vem de checar o estado antes de escrever -- vem do `with_lock`: qualquer leitura de
# modo_atendimento feita fora dessa transação (por exemplo, o dispatcher da Fase 6/7 decidindo se
# envia uma mensagem automática) tem que tomar o mesmo lock antes de agir, ou a garantia não vale.
# Fase 3 não tem dispatcher ainda; este serviço só deixa a trava pronta pra quando ele existir.
#
# Idempotente de propósito: assumir uma conversa já humana, ou devolver uma já lavinia, não é erro
# -- é um no-op que não reescreve modo_atendimento_entrou_em nem duplica o evento.
#
# CP-05 (P1-026-02; SSOT §3.2, §23.3, §28.40): a projeção passa pelo mecanismo durável
# OperationalEngine::ProjectionReconciler -- o pedido de projeção é gravado junto com a transição,
# e `flush` roda SEMPRE depois do lock, inclusive no no-op: repetir "Assumir"/"Devolver" depois de
# uma projeção que falhou conserta o card em vez de deixá-lo stale (o reconciliador também o faria
# sozinho, independentemente do endpoint).
#
# CP-05 (P1-018-01, §17.2 + §18.2): o handoff real pode deixar o lead em modo humano com o
# responsável Comercial pendente (lacuna do SSOT, ver OperationalEngine::CommercialResponsibleResolver).
# Assumir esse lead grava o usuário como responsável (§18.2 "responsavel_atual_id = usuário") sem
# reabrir a intervenção -- o modo já era humano desde o handoff.
module OperationalEngine
  class TakeoverService
    def self.assumir!(lead:, user_id:)
      new(lead).assumir!(user_id)
    end

    def self.devolver!(lead:)
      new(lead).devolver!
    end

    def initialize(lead)
      @lead = lead
    end

    def assumir!(user_id)
      @lead.with_lock do
        if @lead.modo_atendimento_humano?
          claim_pending_responsavel!(user_id) if @lead.responsavel_atual_id.nil?
          next
        end

        @lead.update!(
          modo_atendimento: 'humano',
          responsavel_atual_id: user_id,
          modo_atendimento_entrou_em: Time.current,
          # §18.2: nenhum envio automático pode estar pendente enquanto um humano está na conversa.
          aguardando_resposta: false,
          # §18.2 "recovery inativa; próxima recovery null" -- Fase 7 ainda não dispara recovery,
          # mas o estado já fica correto pra quando o dispatcher existir.
          recuperacao_status: 'inativa',
          proxima_recuperacao_em: nil
        )
        write_event('intervencao_humana_iniciada', responsavel_atual_id: user_id)
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'assumir')
      end

      # Fora do with_lock de propósito: a sincronização visual toca o Postgres nativo, um banco
      # diferente do Supabase -- não vale segurar o lock de linha do Engine pela viagem de rede extra.
      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    def devolver!
      @lead.with_lock do
        next if @lead.modo_atendimento_lavinia?

        previous_responsavel = @lead.responsavel_atual_id
        @lead.update!(
          modo_atendimento: 'lavinia',
          responsavel_atual_id: nil,
          modo_atendimento_entrou_em: Time.current
        )
        # §18.3: "timers antigos não ressuscitam" -- não há nada aqui que reative um timer, de
        # propósito. Um novo timer, quando existir (Fase 7), nasce do estado atual do lead, não
        # de um valor congelado antes do humano assumir.
        write_event('intervencao_humana_encerrada', responsavel_atual_id: previous_responsavel)
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'devolver')
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    private

    def claim_pending_responsavel!(user_id)
      @lead.update!(responsavel_atual_id: user_id)
      write_event('responsavel_alterado', de: nil, para: user_id, motivo: 'assumir_responsavel_pendente')
      OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'assumir')
    end

    # Grava direto (não via EventWriter/IdempotencyGuard): esta não é uma "entrada" de evento
    # externo pra deduplicar -- é a consequência de uma transição de estado que o `with_lock` +
    # early-return acima já torna idempotente. Ver o docstring do EventWriter.
    def write_event(event_type, **extra_metadata)
      OperationalEngine::LeadEvent.create!(
        lead: @lead,
        event_type: event_type,
        source: 'human',
        metadata: extra_metadata.merge(correlation_id: SecureRandom.uuid)
      )
    end
  end
end
