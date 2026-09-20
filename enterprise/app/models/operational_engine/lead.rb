# Fonte de verdade do negócio (Contrato Técnico do Marco 1, §5.1). Vive no Supabase via
# OperationalEngine::Record -- nunca no Postgres nativo do Chatwoot. `Sales::Lead` é a projeção
# visual (Kanban); nada aqui lê ou escreve nela, e o inverso também não deve acontecer (§5.3).
#
# Enums declarados a partir do valor congelado no SSOT §6.2, não por posição -- uma reordenação
# nunca troca o significado de um valor já gravado.
module OperationalEngine
  class Lead < OperationalEngine::Record
    self.table_name = 'leads'
    self.primary_key = 'lead_id'

    def self.string_enum(values)
      values.index_by(&:itself)
    end

    has_many :events, class_name: 'OperationalEngine::LeadEvent', foreign_key: :lead_id, inverse_of: :lead

    enum etapa_prospect: string_enum(%w[backlog contatado em_conversa qualificado agendado]), validate: true, prefix: true
    enum lead_status: string_enum(%w[ativo encerrado]), validate: true, prefix: true
    enum qualificacao_status: string_enum(%w[em_qualificacao qualificado nao_qualificado nao_concluido]), validate: true, prefix: true
    enum recuperacao_status: string_enum(%w[inativa ativa]), validate: true, prefix: true
    enum agendamento_status: string_enum(%w[nao_iniciado em_andamento confirmado callback_registrado callback_realizado cancelado]),
         validate: true, prefix: true
    enum orcamento_status: string_enum(%w[nao_solicitado em_dimensionamento informado personalizado]), validate: true, prefix: true
    enum resultado_comercial: string_enum(%w[em_aberto ganho perdido]), validate: true, prefix: true
    enum modo_atendimento: string_enum(%w[lavinia humano]), validate: true, prefix: true
    enum frente_operacional: string_enum(%w[prospeccao comercial]), validate: true, prefix: true
    enum etapa_comercial: string_enum(%w[oportunidade em_acompanhamento ganho perdido]), validate: { allow_nil: true }, prefix: true
    enum propensao_fechamento: string_enum(%w[nao_classificado frio morno quente]), validate: true, prefix: true
    enum intencao_comercial: string_enum(%w[informativo avaliando quer_orcamento quer_avancar]), validate: { allow_nil: true }, prefix: true
    enum cobertura_status: string_enum(%w[atendida fora_cobertura a_validar nao_identificada]), validate: { allow_nil: true }, prefix: true
    enum tipo_conversao: string_enum(%w[agendamento callback]), validate: { allow_nil: true }, prefix: true
    enum motivo_handoff: string_enum(%w[avanco_comercial orcamento_personalizado excecao]), validate: { allow_nil: true }, prefix: true
    enum motivo_encerramento: string_enum(%w[sem_resposta sem_interesse nao_qualificado cliente_atual nao_contatar fora_escopo outro]),
         validate: { allow_nil: true }, prefix: true

    before_validation :normalize_telefone

    validates :telefone, presence: true, uniqueness: true

    private

    def normalize_telefone
      self.telefone = Sales::Prospecting::PhoneNormalizer.normalize(telefone) || telefone
    end
  end
end
