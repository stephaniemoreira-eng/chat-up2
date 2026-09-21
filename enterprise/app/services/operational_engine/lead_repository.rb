# Identidade/dedupe do §5.5 e testes 28.7/28.8: um lead é identificado por (conta_id, telefone),
# nunca por um id externo isolado. find_or_create precisa ser seguro sob concorrência -- dois
# webhooks quase simultâneos pro mesmo número não podem criar dois leads.
module OperationalEngine
  class LeadRepository
    def self.find_or_create_by_telefone(conta_id:, telefone:, attributes: {})
      new.find_or_create_by_telefone(conta_id: conta_id, telefone: telefone, attributes: attributes)
    end

    def find_or_create_by_telefone(conta_id:, telefone:, attributes: {})
      normalized = Sales::Prospecting::PhoneNormalizer.normalize(telefone) || telefone

      find(conta_id, normalized) || create(conta_id, telefone, attributes)
    end

    private

    def find(conta_id, normalized_telefone)
      OperationalEngine::Lead.find_by(conta_id: conta_id, telefone: normalized_telefone)
    end

    def create(conta_id, telefone, attributes)
      OperationalEngine::Lead.create!(attributes.merge(conta_id: conta_id, telefone: telefone))
    rescue ActiveRecord::RecordInvalid
      # Corrida perdida: outro processo criou o lead entre o find e o create acima. A
      # uniqueness de (conta_id, telefone) já garantiu que não há dois -- só falta pegar o que
      # ganhou a corrida.
      normalized = Sales::Prospecting::PhoneNormalizer.normalize(telefone) || telefone
      find(conta_id, normalized) || raise
    end
  end
end
