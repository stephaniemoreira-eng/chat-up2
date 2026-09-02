# Pesos do SCAN v1 (UP2_SCAN_Instrucao_Construcao_Workflow_n8n_v1.md +
# UP2_SCAN_Arquitetura_Pre_Diagnostico_v1.docx). Ponto unico de calibracao: mexer aqui, nunca
# espalhar numero magico pelos services. Pesos internos de cada pilar sao hipotese inicial da
# Stephanie/IA (2026-09-02), a recalibrar com dados reais (secao 15 do docx).
#
# Recencia/engajamento do Instagram ficam de fora do v1 (o docx original assumia Apify; o
# up2-scanner nao coleta isso sem risco de bloqueio) -- ver docs/fork (12-saas-prospeccao-
# multicliente.md) para o registro completo dessa decisao. CNAE (pilar ICP) tambem fica de fora
# ate existir uma fonte confiavel de CNPJ a partir do lead.
module Sales::Prospecting::ScanWeights
  PILARES = { website: 30, maps: 30, instagram: 25, icp: 15 }.freeze

  WEBSITE = {
    performance: 10,   # PageSpeed Performance Score (0-100) -> proporcional
    seo: 10,           # PageSpeed SEO Score (0-100) -> proporcional
    best_practices: 5, # PageSpeed Best Practices Score (0-100) -> proporcional -- secundario no docx
    comercial: 5        # sinais no HTML: whatsapp (2) + cta (2) + ecommerce (1), via up2-scanner
  }.freeze

  MAPS = {
    presenca: 5,         # Place Details respondeu (empresa ainda existe/e encontravel)
    business_status: 5,  # OPERATIONAL = pontos cheios; CLOSED_* = zero + alerta
    rating: 10,           # nota/5 * 10, arredondado
    avaliacoes: 5,        # faixas por volume de avaliacoes
    completude: 5         # website + telefone + horario presentes, no Place Details
  }.freeze

  INSTAGRAM = {
    perfil_encontrado: 5,
    seguidores: 5,  # faixas
    posts: 5,       # faixas
    bio: 10         # IA classifica 2 criterios (clareza + profissionalismo), 5pts cada -- nunca a IA decide o numero, so sim/nao por criterio
  }.freeze

  ICP = {
    segmento: 7,          # segmento buscado bate com categoria/texto da empresa
    evidencia_b2b: 4,      # palavras-chave de atuação B2B no site
    categoria_google: 4    # Place Details trouxe primaryType/categoria
    # CNAE fica de fora do v1 -- falta fonte de CNPJ (ver nota no topo do arquivo)
  }.freeze

  FAIXAS = {
    (0..49) => 'baixa_prioridade',
    (50..69) => 'revisao_humana',
    (70..100) => 'revisao_prioritaria'
  }.freeze

  def self.faixa_for(score)
    FAIXAS.find { |range, _| range.cover?(score) }&.last || 'baixa_prioridade'
  end
end
