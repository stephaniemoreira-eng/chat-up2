# Identidade/dedupe do §5.5 e testes 28.7/28.8: um lead é identificado por (conta_id, telefone),
# nunca por um id externo isolado. find_or_create precisa ser seguro sob concorrência -- dois
# webhooks quase simultâneos pro mesmo número não podem criar dois leads.
module OperationalEngine
  class LeadRepository
    def self.find_or_create_by_telefone(conta_id:, telefone:, attributes: {})
      new.find_or_create_by_telefone(conta_id: conta_id, telefone: telefone, attributes: attributes)
    end

    # Só a busca, sem criar -- pra quem (InboundProcessor, o listener no auto-assume) precisa
    # saber se um lead já existe sem ter atributos de criação pra oferecer. Normaliza por dentro
    # pelo mesmo motivo do find_or_create_by_telefone: o telefone bruto de quem chama (Contact do
    # Chatwoot) não tem garantia de já estar no formato salvo em leads.telefone.
    def self.find_by_telefone(conta_id:, telefone:)
      new.find_by_telefone(conta_id: conta_id, telefone: telefone)
    end

    def find_or_create_by_telefone(conta_id:, telefone:, attributes: {})
      find_by_telefone(conta_id: conta_id, telefone: telefone) || create(conta_id, telefone, attributes)
    end

    def find_by_telefone(conta_id:, telefone:)
      find(conta_id, normalize(telefone))
    end

    private

    def normalize(telefone)
      Sales::Prospecting::PhoneNormalizer.normalize(telefone) || telefone
    end

    def find(conta_id, normalized_telefone)
      OperationalEngine::Lead.find_by(conta_id: conta_id, telefone: normalized_telefone)
    end

    def create(conta_id, telefone, attributes)
      OperationalEngine::Lead.create!(attributes.merge(conta_id: conta_id, telefone: telefone))
    rescue ActiveRecord::RecordInvalid
      # Corrida perdida: outro processo criou o lead entre o find e o create acima. A
      # uniqueness de (conta_id, telefone) já garantiu que não há dois -- só falta pegar o que
      # ganhou a corrida.
      find(conta_id, normalize(telefone)) || raise
    end
  end
end
