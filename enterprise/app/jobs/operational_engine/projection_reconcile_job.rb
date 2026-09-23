# CP-05 (P1-025-04, P1-026-02; SSOT §3.2, §23.3). Reconciliador durável da projeção
# Supabase → Sales::*: reprocessa os pedidos de projeção vencidos (OperationalEngine::ProjectionRequest
# pendente com next_attempt_at no passado) -- os que falharam na tentativa inline logo após a
# mutação, ou cuja tentativa inline nunca chegou a rodar (processo caiu depois do commit).
#
# Independe do endpoint que originou a mutação: um card que ficou na fotografia antiga converge
# mesmo que ninguém repita a ação. O limite de tentativas e o sinal de erro terminal vivem em
# OperationalEngine::ProjectionReconciler.
module OperationalEngine
  class ProjectionReconcileJob < ApplicationJob
    queue_as :scheduled_jobs

    BATCH_SIZE = 200

    def perform
      OperationalEngine::ProjectionRequest.due.order(:next_attempt_at).limit(BATCH_SIZE).pluck(:lead_id).each do |lead_id|
        OperationalEngine::ProjectionReconciler.new(lead_id).flush
      end
    end
  end
end
