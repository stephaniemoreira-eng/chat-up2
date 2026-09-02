# Classifica a bio do Instagram em 2 criterios fixos para o pilar Instagram do SCAN v1. A IA
# NUNCA decide pontos aqui -- so devolve sim/nao por criterio; ScanWeights::INSTAGRAM[:bio] e quem
# converte isso em pontos (ver ScanService). Reusa a chave do Captain AI (CAPTAIN_OPEN_AI_API_KEY)
# em vez de criar uma integracao nova so pra isso.
class Sales::Prospecting::BioClassifierService
  TIMEOUT_SECONDS = 15
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Voce classifica a bio de um perfil de Instagram comercial em dois criterios objetivos.
    Responda SOMENTE com um JSON no formato exato:
    {"deixa_claro_o_que_a_empresa_faz": true|false, "e_profissional_bem_estruturada": true|false}
    Nao inclua nenhum texto alem do JSON. Nao invente uma nota numerica -- so os dois booleanos.
  PROMPT

  def self.call(bio)
    new(bio).call
  end

  def initialize(bio)
    @bio = bio
  end

  # Retorna nil se faltar bio/chave ou a chamada falhar -- tratado como dado_nao_encontrado.
  def call
    return nil if @bio.blank? || api_key.blank?

    response = HTTParty.post(
      endpoint,
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" },
      body: request_body.to_json,
      timeout: TIMEOUT_SECONDS
    )
    return nil unless response.success?

    parse(response.parsed_response)
  rescue StandardError => e
    Rails.logger.error("[Sales::Prospecting::BioClassifierService] #{e.class}: #{e.message}")
    nil
  end

  private

  def request_body
    {
      model: model,
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: @bio }
      ]
    }
  end

  def parse(data)
    content = data.dig('choices', 0, 'message', 'content')
    return nil if content.blank?

    parsed = JSON.parse(content)
    {
      clareza: parsed['deixa_claro_o_que_a_empresa_faz'] == true,
      profissionalismo: parsed['e_profissional_bem_estruturada'] == true
    }
  rescue JSON::ParserError
    nil
  end

  def endpoint
    base = GlobalConfigService.load('CAPTAIN_OPEN_AI_ENDPOINT', '').presence || 'https://api.openai.com/'
    "#{base.chomp('/')}/v1/chat/completions"
  end

  def model
    GlobalConfigService.load('CAPTAIN_OPEN_AI_MODEL', '').presence || 'gpt-4.1-mini'
  end

  def api_key
    GlobalConfigService.load('CAPTAIN_OPEN_AI_API_KEY', '')
  end
end
