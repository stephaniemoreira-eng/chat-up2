# Único caminho pra gravar um LeadEvent a partir de um evento externo (§7 + §5.5). Fase 2 cobre
# só o registro append-only do evento, guardado por idempotência -- decidir o que cada tipo de
# evento MUDA no Lead é regra de negócio das fases seguintes (inbound processor, Lavínia,
# dispatcher), não deste writer.
module OperationalEngine
  class EventWriter
    def self.call(...)
      new(...).call
    end

    def initialize(lead:, event_type:, source:, external_source:, external_id:, metadata: {})
      @lead = lead
      @event_type = event_type
      @source = source
      @external_source = external_source
      @external_id = external_id
      @metadata = metadata
    end

    def call
      OperationalEngine::IdempotencyGuard.call(
        conta_id: @lead.conta_id,
        event_type: @event_type,
        external_source: @external_source,
        external_id: @external_id
      ) do |correlation_id|
        OperationalEngine::LeadEvent.create!(
          lead: @lead,
          event_type: @event_type,
          source: @source,
          metadata: @metadata.merge(correlation_id: correlation_id)
        )
      end
    end
  end
end
