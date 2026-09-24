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
#
# CP-06 (P1-026-01, P2-026-01, RISK-026-01; SSOT §7.3, §7.4, §18.2, §18.3, §28.19, §28.22):
# - Devolver só reativa a Lavínia DEPOIS da sincronização (OperationalEngine::DevolucaoSync), na
#   mesma transação: se a sincronização falha, nada é gravado -- o lead continua humano e com o
#   responsável, e o erro sobe para o operador (DevolucaoSync::SyncError -> 422).
# - Timers antigos não ressuscitam: Devolver não restaura aguardando_resposta/recovery (ficam
#   falso/inativa/nulo) -- novo timer só nasce do estado atual. Ativações de abertura ainda
#   autorizadas são canceladas ao Assumir, então o Dispatcher não retoma uma abertura antiga depois
#   do Devolver. Timers do up2-agents criados antes da mudança de modo são recusados no post
#   (OutboundSendGate, carimbo `up2_automation.created_at`, PR coordenada).
# - Timeline (P2-026-01): além de intervencao_humana_iniciada/encerrada, cada transição grava
#   modo_atendimento_alterado e responsavel_alterado com de/para/motivo/executado_por -- quem
#   assumiu, o que havia antes, quando devolveu e o estado resultante saem só dos eventos.
#
# CP-16B (P2-VAL-20, decisão da Stéphanie em 24/09/2026 -- "A LAVÍNIA ANALISA A CONVERSA NOVAMENTE E
# VÊ AONDE O CONTEXTO TERMINA E INTERPRETA QUAL O ultimo_ponto PARA CONTINUAÇÃO DA CONVERSA, SE
# NECESSÁRIO."): depois do commit da devolução (fora do lock), agenda o turno silencioso de
# ressincronização da Lavínia (OperationalEngine::DevolucaoResync). Ele só roda depois que a
# devolução já está gravada e nunca a desfaz: falhar ali mantém o `ultimo_ponto` anterior.
module OperationalEngine
  class TakeoverService
    def self.assumir!(lead:, user_id:, motivo: 'assumir')
      new(lead).assumir!(user_id, motivo)
    end

    def self.devolver!(lead:, user_id: nil)
      new(lead).devolver!(user_id)
    end

    def initialize(lead)
      @lead = lead
    end

    def assumir!(user_id, motivo = 'assumir')
      @lead.with_lock do
        if @lead.modo_atendimento_humano?
          claim_pending_responsavel!(user_id) if @lead.responsavel_atual_id.nil?
          next
        end

        before = transition_snapshot
        @lead.update!(
          modo_atendimento: 'humano',
          responsavel_atual_id: user_id,
          modo_atendimento_entrou_em: Time.current,
          # §18.2: nenhum envio automático pode estar pendente enquanto um humano está na conversa.
          aguardando_resposta: false,
          # §18.2 "recovery inativa; próxima recovery null; cancelar timers da Lavínia".
          recuperacao_status: 'inativa',
          proxima_recuperacao_em: nil
        )
        write_transition_events('intervencao_humana_iniciada', before, motivo, user_id, responsavel_atual_id: user_id)
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'assumir')
      end

      # Fora do with_lock de propósito: a sincronização visual e o cancelamento das ativações tocam
      # o Postgres nativo, um banco diferente do Supabase.
      cancel_pending_activations
      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    def devolver!(user_id = nil)
      devolucao_id = nil
      @lead.with_lock do
        next if @lead.modo_atendimento_lavinia?

        # §18.3: sincroniza ANTES de reativar. SyncError aqui desfaz a transação inteira.
        sync = OperationalEngine::DevolucaoSync.call(@lead)
        before = transition_snapshot
        reactivate_lavinia!(sync[:lead_attributes])
        devolucao_id = write_transition_events('intervencao_humana_encerrada', before, 'devolver', user_id,
                                               responsavel_atual_id: before[:responsavel_atual_id], sincronizacao: sync[:sincronizacao])
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'devolver')
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      # Só numa devolução real (no-op não reagenda) e só depois do commit.
      OperationalEngine::DevolucaoResync.schedule(@lead, devolucao_id) if devolucao_id
      @lead
    end

    private

    def reactivate_lavinia!(synced_attributes)
      @lead.update!(
        **synced_attributes,
        modo_atendimento: 'lavinia',
        responsavel_atual_id: nil,
        modo_atendimento_entrou_em: Time.current,
        # §18.3 "timers antigos não ressuscitam": nada pendente de antes volta a valer.
        aguardando_resposta: false,
        recuperacao_status: 'inativa',
        proxima_recuperacao_em: nil
      )
    end

    def transition_snapshot
      { modo_atendimento: @lead.modo_atendimento, responsavel_atual_id: @lead.responsavel_atual_id }
    end

    def claim_pending_responsavel!(user_id)
      @lead.update!(responsavel_atual_id: user_id)
      write_event('responsavel_alterado', SecureRandom.uuid,
                  de: nil, para: user_id, motivo: 'assumir_responsavel_pendente', executado_por: user_id)
      OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'assumir')
    end

    # Mesma correlation_id em todos os eventos da transição (uma ação lógica, várias semânticas).
    # Devolve a correlation_id -- é a identidade da devolução para o turno de ressincronização (CP-16B).
    def write_transition_events(intervencao_event, before, motivo, user_id, **intervencao_metadata)
      correlation_id = SecureRandom.uuid
      common = { motivo: motivo, executado_por: user_id }
      write_event(intervencao_event, correlation_id, **intervencao_metadata, **common)
      write_event('modo_atendimento_alterado', correlation_id, de: before[:modo_atendimento], para: @lead.modo_atendimento, **common)
      if before[:responsavel_atual_id] != @lead.responsavel_atual_id
        write_event('responsavel_alterado', correlation_id, de: before[:responsavel_atual_id], para: @lead.responsavel_atual_id, **common)
      end
      correlation_id
    end

    # Grava direto (não via EventWriter/IdempotencyGuard): esta não é uma "entrada" de evento
    # externo pra deduplicar -- é a consequência de uma transição de estado que o `with_lock` +
    # early-return acima já torna idempotente. Ver o docstring do EventWriter.
    def write_event(event_type, correlation_id, **metadata)
      OperationalEngine::LeadEvent.create!(
        lead: @lead,
        event_type: event_type,
        source: 'human',
        metadata: metadata.merge(correlation_id: correlation_id)
      )
    end

    # RISK-026-01: uma abertura do Dispatcher autorizada antes do Assumir não pode sobreviver a ele
    # (senão, depois do Devolver, o Dispatcher a retomaria). Best-effort fora do lock: se falhar, o
    # OutboundSendGate continua barrando enquanto o lead estiver humano.
    #
    # CP-13 (P1-VAL-12, §18.2 "cancelar timers da Lavínia", 28.23): o mesmo para a tentativa de
    # recovery autorizada -- além do timer zerado no lead acima e da revalidação no post.
    def cancel_pending_activations
      contact_ids = [@lead.upsales_contact_id, conversation_contact_id].compact.uniq
      return if contact_ids.empty?

      [OperationalEngine::OriginationActivation, OperationalEngine::RecoveryActivation].each do |klass|
        contact_ids.each do |contact_id|
          klass.pending_for_contact(account_id: @lead.conta_id, contact_id: contact_id).each do |activation|
            activation.transition!('cancelled', motivo: 'atendimento_humano') if activation.lead_id == @lead.lead_id
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error("[OperationalEngine::TakeoverService] lead=#{@lead.lead_id} falha ao cancelar ativações: #{e.class}: #{e.message}")
    end

    def conversation_contact_id
      return nil if @lead.upsales_conversation_atual_id.blank?

      ::Conversation.where(id: @lead.upsales_conversation_atual_id, account_id: @lead.conta_id).pick(:contact_id)
    end
  end
end
