# CP-16A (P2-VAL-17; decisão da Stéphanie em 24/09/2026 -- o texto do e-mail da 3ª tentativa de
# recovery deve "SER AJUSTÁVEL"). Assunto e corpo configuráveis POR CONTA no Super Admin de
# configuração de agente (UpSales::AgentTenant#recovery_email_subject / #recovery_email_body). Vazio =
# o modelo neutro do CP-13 (RecoveryMailer), que continua sendo o padrão.
#
# Placeholders (os ÚNICOS aceitos -- qualquer outro é recusado ao salvar, ver UpSales::AgentTenant):
#   {{nome}}    nome do lead (vazio se desconhecido)
#   {{empresa}} empresa do lead (vazio se desconhecida)
#   {{persona}} nome de quem assina (ENV UP_SALES_RECOVERY_EMAIL_PERSONA, padrão "Lavínia")
#   {{marca}}   nome da conta (padrão "nossa equipe")
#
# Segurança: substituição textual de uma lista fechada -- nada é avaliado (sem ERB/interpolação Ruby,
# sem acesso a métodos do lead). O e-mail é text/plain, então não há HTML a escapar; os VALORES
# substituídos perdem caracteres de controle (quebras de linha inclusive) e são truncados, e o assunto
# final vira uma linha só -- um nome malicioso não injeta cabeçalho nem parágrafos. O endereço de
# e-mail nunca é um placeholder nem vai para log.
module OperationalEngine
  class RecoveryEmailTemplate
    PLACEHOLDERS = %w[nome empresa persona marca].freeze
    PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z_]+)\s*\}\}/
    VALUE_MAX_LENGTH = 120
    SUBJECT_MAX_LENGTH = 200
    BODY_MAX_LENGTH = 5000

    def self.unknown_placeholders(text)
      text.to_s.scan(PLACEHOLDER_PATTERN).flatten.map(&:downcase).uniq - PLACEHOLDERS
    end

    def initialize(values)
      @values = PLACEHOLDERS.index_with { |key| sanitize(values[key.to_sym]) }
    end

    def render_subject(template)
      render(template).squish.truncate(SUBJECT_MAX_LENGTH)
    end

    def render_body(template)
      render(template.to_s.gsub("\r\n", "\n")).strip.truncate(BODY_MAX_LENGTH)
    end

    private

    def render(template)
      template.to_s.gsub(PLACEHOLDER_PATTERN) { @values.fetch(Regexp.last_match(1).downcase, '') }
    end

    def sanitize(value)
      value.to_s.gsub(/[[:cntrl:]]/, ' ').squish.truncate(VALUE_MAX_LENGTH)
    end
  end
end
