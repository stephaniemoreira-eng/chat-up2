# CP-05 (P1-025-04, P1-026-02; SSOT §3.2, §3.4, §23.3, §28.40, §29.3). Mecanismo ÚNICO de
# projeção pós-commit Supabase → Sales::* (cards/tags do Kanban Prospect e Comercial).
#
# Problema que resolve: toda mutação do Engine persiste o fato dentro do `lead.with_lock` e só
# depois, fora do lock (outro banco), projeta no CRM. Se a projeção falhava (ex.:
# ProjectionIntegrityError, banco nativo indisponível), o fato ficava confirmado no Engine, o
# request respondia erro e o card ficava na fotografia antiga para sempre -- e um retry idempotente
# (no-op, "já está humano") nem tentava projetar de novo.
#
# Como funciona:
# 1. `request!` grava/renova um OperationalEngine::ProjectionRequest DENTRO da mesma transação do
#    fato (mesmo banco) -- durável e atômico com a mutação: se o fato existe, o pedido existe.
# 2. `flush` tenta projetar logo em seguida, fora do lock. Sucesso marca a linha sincronizada (só
#    se ninguém pediu uma versão mais nova no meio -- compare-and-set em `version`). Falha NÃO sobe
#    para quem chamou (o fato já está confirmado; responder erro faria o operador repetir a ação):
#    conta a tentativa, agenda a próxima com backoff e loga.
# 3. OperationalEngine::ProjectionReconcileJob (cron) reprocessa os pedidos vencidos até sucesso
#    ou MAX_ATTEMPTS; ao esgotar, a linha vira `falhou` (terminal, consultável) e o erro vai para o
#    ChatwootExceptionTracker -- sinal operacional de §29.3. `reprocess!` rearma manualmente.
#
# A projeção é sempre recalculada a partir da fotografia inteira do lead (SalesProjectionSync e
# ComercialProjectionSync são idempotentes), então repetir nunca duplica fato nem evento de negócio:
# nada aqui escreve em `leads` ou `lead_events`.
#
# API para os serviços do Engine (inclusive Assumir/Devolver -- CP-06 consome este mesmo contrato):
#
#   lead.with_lock do
#     ...mutação + LeadEvent...
#     OperationalEngine::ProjectionReconciler.request!(lead, motivo: 'assumir')
#   end
#   OperationalEngine::ProjectionReconciler.flush(lead)   # fora do lock, sempre
#
# Num no-op idempotente (nada mudou), chame só `flush`: se uma tentativa anterior deixou a projeção
# pendente, ela é reparada agora (P1-026-02: repetir "Assumir" conserta o card).
module OperationalEngine
  class ProjectionReconciler
    MAX_ATTEMPTS = 8
    MAX_BACKOFF = 1.hour
    # O primeiro pedido nasce com uma folga antes de o job poder pegá-lo: quem pediu já vai tentar
    # inline logo depois do commit, e o job não precisa correr em paralelo com essa tentativa.
    INLINE_GRACE = 1.minute
    LOG_TAG = '[OperationalEngine::ProjectionReconciler]'.freeze

    class OutsideTransactionError < StandardError; end

    def self.request!(lead, motivo:)
      unless OperationalEngine::Record.connection.transaction_open?
        raise OutsideTransactionError, 'request! precisa rodar dentro do lead.with_lock da mutação'
      end

      now = Time.current
      renewed = OperationalEngine::ProjectionRequest.where(lead_id: lead.lead_id).update_all( # rubocop:disable Rails/SkipsModelValidations
        ["version = version + 1, status = 'pendente', motivo = ?, attempts = 0, next_attempt_at = ?, last_error = NULL, updated_at = ?",
         motivo, now + INLINE_GRACE, now]
      )
      return if renewed.positive?

      # Sem corrida na criação: todo request! roda sob o lock de linha do lead.
      OperationalEngine::ProjectionRequest.create!(
        lead_id: lead.lead_id, conta_id: lead.conta_id, motivo: motivo, next_attempt_at: now + INLINE_GRACE
      )
    end

    def self.flush(lead)
      new(lead.lead_id).flush
    end

    # Rearma manualmente um pedido que esgotou as tentativas (status `falhou`) e tenta de novo.
    def self.reprocess!(lead_id)
      OperationalEngine::ProjectionRequest.where(lead_id: lead_id).update_all( # rubocop:disable Rails/SkipsModelValidations
        ["version = version + 1, status = 'pendente', attempts = 0, next_attempt_at = ?, updated_at = ?", Time.current, Time.current]
      )
      new(lead_id).flush
    end

    def initialize(lead_id)
      @lead_id = lead_id
    end

    # :nada_pendente | :sincronizado | :falhou
    def flush
      pending = OperationalEngine::ProjectionRequest.status_pendente.find_by(lead_id: @lead_id)
      return :nada_pendente unless pending

      attempt(pending)
    end

    private

    def attempt(pending)
      # Relê o lead DEPOIS de ler o pedido: a fotografia projetada é, no mínimo, a da versão pedida.
      lead = OperationalEngine::Lead.find(@lead_id)
      OperationalEngine::SalesProjectionSync.call(lead)
      OperationalEngine::ComercialProjectionSync.call(lead)
      # CP-06: o modo também é projetado na conversa do canal (quem a Lavínia atende no up2-agents).
      OperationalEngine::ConversationModeProjection.call(lead)
      mark_synced(pending)
      :sincronizado
    rescue StandardError => e
      register_failure(pending, e)
      :falhou
    end

    def mark_synced(pending)
      now = Time.current
      scope = OperationalEngine::ProjectionRequest.where(lead_id: @lead_id, version: pending.version, status: 'pendente')
      scope.update_all(status: 'sincronizado', synced_at: now, last_error: nil, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end

    def register_failure(pending, error)
      attempts = pending.attempts + 1
      terminal = attempts >= MAX_ATTEMPTS
      now = Time.current
      scope = OperationalEngine::ProjectionRequest.where(lead_id: @lead_id, version: pending.version)
      scope.update_all( # rubocop:disable Rails/SkipsModelValidations
        attempts: attempts, last_attempt_at: now, last_error: "#{error.class}: #{error.message}".truncate(1000),
        status: terminal ? 'falhou' : 'pendente', next_attempt_at: terminal ? nil : now + backoff(attempts), updated_at: now
      )
      report(pending, error, attempts, terminal)
    rescue StandardError => e
      # Nem a contabilidade da falha foi possível (ex.: Supabase fora). O pedido continua pendente
      # e vence logo após o commit (INLINE_GRACE) -- o job o reprocessa quando o banco voltar.
      Rails.logger.error("#{LOG_TAG} lead=#{@lead_id} falha ao registrar tentativa: #{e.class}: #{e.message}")
    end

    def backoff(attempts)
      [(2**attempts).minutes, MAX_BACKOFF].min
    end

    def report(pending, error, attempts, terminal)
      payload = { lead_id: @lead_id, conta_id: pending.conta_id, motivo: pending.motivo, attempts: attempts,
                  terminal: terminal, error: "#{error.class}: #{error.message}" }
      if terminal
        Rails.logger.error("#{LOG_TAG} projeção esgotou as tentativas #{payload.to_json}")
        ChatwootExceptionTracker.new(error, account: Account.find_by(id: pending.conta_id)).capture_exception
      else
        Rails.logger.warn("#{LOG_TAG} projeção falhou, nova tentativa agendada #{payload.to_json}")
      end
    end
  end
end
