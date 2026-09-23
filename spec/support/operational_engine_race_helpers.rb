# CP-01 (P1-018-05): simula a corrida "fato mais novo entra enquanto uma ação antiga espera o
# lock". A ação resolve o lead (fotografia antiga, em memória); antes de ela tomar o with_lock,
# outro processo persiste o fato novo. Como with_lock relê a linha, o fato novo tem que vencer.
module OperationalEngineRaceHelpers
  def persist_newer_fact_before_lock(**attributes)
    allow(OperationalEngine::Tools::ResolveLeadFromConversation).to receive(:call).and_wrap_original do |original, **kwargs|
      stale = original.call(**kwargs)
      OperationalEngine::Lead.find(stale.lead_id).update!(**attributes)
      stale
    end
  end
end

RSpec.configure do |config|
  config.include OperationalEngineRaceHelpers
end
