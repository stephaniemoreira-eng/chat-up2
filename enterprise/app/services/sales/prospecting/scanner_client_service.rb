# Chama o up2-scanner (servico proprio, self-hosted, repo stephaniemoreira-eng/up2-scanner) para
# os sinais de site (WhatsApp/e-commerce/CTA) e Instagram (perfil/seguidores/posts/bio) do SCAN v1.
# Mesmo servico ja usado pelo Fluxo 2 (PScore) do n8n -- nao duplica scraping.
class Sales::Prospecting::ScannerClientService
  TIMEOUT_SECONDS = 30

  def self.call(website:, empresa:)
    new(website: website, empresa: empresa).call
  end

  def initialize(website:, empresa:)
    @website = website
    @empresa = empresa
  end

  # Retorna nil se faltar configuracao ou a chamada falhar -- os pilares Website/Instagram tratam
  # isso como dados_nao_encontrados, nao como erro fatal do scan inteiro.
  def call
    return nil if @website.blank? || scanner_url.blank? || scanner_token.blank?

    response = HTTParty.post(
      "#{scanner_url}/scan",
      headers: { 'Content-Type' => 'application/json', 'X-Scanner-Token' => scanner_token },
      body: { site: @website, empresa: @empresa }.to_json,
      timeout: TIMEOUT_SECONDS
    )
    return nil unless response.success?

    response.parsed_response
  rescue StandardError => e
    Rails.logger.error("[Sales::Prospecting::ScannerClientService] #{@website}: #{e.class}: #{e.message}")
    nil
  end

  private

  def scanner_url
    GlobalConfigService.load('SCANNER_URL', '')
  end

  def scanner_token
    GlobalConfigService.load('SCANNER_TOKEN', '')
  end
end
