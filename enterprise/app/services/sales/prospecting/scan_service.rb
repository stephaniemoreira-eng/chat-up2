# Motor de score do SCAN v1 (algoritmo determinístico, ver ScanWeights). Orquestra as coletas
# (PageSpeed, Place Details, up2-scanner, classificacao de bio) e grava o resultado no proprio
# Sales::ProspectingResult. So roda para contas com a feature `sales_scan` ligada (opt-in, hoje so
# a UP2 -- ver docs/fork/ADR-0001, secao "sales_scan").
#
# Regra do SCAN v1: o algoritmo e a autoridade sobre a pontuacao, a IA so entra para classificar a
# bio do Instagram (2 criterios sim/nao -- nunca um numero). Ver
# UP2_SCAN_Arquitetura_Pre_Diagnostico_v1.docx, secoes 4 e 12.
#
# aprovado/liberado_envio ficam sempre false nesta fase de testes, independente do score --
# exigencia explicita do documento-fonte, nao um bug. So mudar isso depois de calibrar com
# amostra real (secao 15 do docx).
class Sales::Prospecting::ScanService
  W = Sales::Prospecting::ScanWeights

  def self.call(result)
    new(result).call
  end

  def initialize(result)
    @result = result
    @dados_nao_encontrados = []
    @alertas = []
  end

  def call
    place_details = Sales::Prospecting::PlaceDetailsService.call(@result.place_id)
    pagespeed = Sales::Prospecting::PageSpeedService.call(@result.website)
    scanner = Sales::Prospecting::ScannerClientService.call(website: @result.website, empresa: @result.name)

    website = website_pillar(pagespeed, scanner)
    maps = maps_pillar(place_details)
    instagram = instagram_pillar(scanner)
    icp = icp_pillar(place_details, scanner)

    pilares = { website: website[:pontos], maps: maps[:pontos], instagram: instagram[:pontos], icp: icp[:pontos] }
    score = pilares.values.sum

    @result.update!(
      scan_status: 'concluido',
      scan_score: score,
      scan_faixa: W.faixa_for(score),
      scan_pilares: pilares,
      scan_evidencias: {
        indicadores: { website: website[:indicadores], maps: maps[:indicadores], instagram: instagram[:indicadores], icp: icp[:indicadores] },
        dados_nao_encontrados: @dados_nao_encontrados,
        alertas: @alertas
      },
      scan_aprovado: false,
      scan_liberado_envio: false,
      scanned_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[Sales::Prospecting::ScanService] result_id=#{@result.id} failed: #{e.class}: #{e.message}")
    @result.update!(scan_status: 'erro', scanned_at: Time.current)
  end

  private

  # ---- Website (30) ----------------------------------------------------------------------

  def website_pillar(pagespeed, scanner)
    if @result.website.blank?
      @dados_nao_encontrados << 'website'
      return { pontos: 0, indicadores: { possui_site: false } }
    end

    pontos = 0
    indicadores = { possui_site: true }

    if pagespeed
      indicadores[:performance_score] = pagespeed[:performance_score]
      indicadores[:seo_score] = pagespeed[:seo_score]
      indicadores[:best_practices_score] = pagespeed[:best_practices_score]
      pontos += proportional(W::WEBSITE[:performance], pagespeed[:performance_score])
      pontos += proportional(W::WEBSITE[:seo], pagespeed[:seo_score])
      pontos += proportional(W::WEBSITE[:best_practices], pagespeed[:best_practices_score])
    else
      @dados_nao_encontrados << 'pagespeed'
    end

    site = scanner&.dig('site') || {}
    comercial = 0
    comercial += 2 if site['has_whatsapp']
    comercial += 2 if site['has_cta']
    comercial += 1 if site['has_ecommerce']
    indicadores[:has_whatsapp] = site['has_whatsapp']
    indicadores[:has_cta] = site['has_cta']
    indicadores[:has_ecommerce] = site['has_ecommerce']
    pontos += comercial

    { pontos: pontos, indicadores: indicadores }
  end

  def proportional(max_points, score_0_100)
    return 0 if score_0_100.nil?

    (max_points * score_0_100 / 100.0).round
  end

  # ---- Google / Maps (30) -----------------------------------------------------------------

  def maps_pillar(details)
    unless details
      @dados_nao_encontrados << 'place_details'
      @alertas << 'Nao foi possivel confirmar o perfil no Google Maps (place_id invalido ou API indisponivel).'
      # rating/user_ratings_total capturados na busca original ainda valem como fallback simples.
      return maps_pillar_from_search_only
    end

    pontos = W::MAPS[:presenca]
    indicadores = { presenca_confirmada: true, business_status: details[:business_status] }

    if details[:business_status] == 'OPERATIONAL'
      pontos += W::MAPS[:business_status]
    elsif details[:business_status].present?
      @alertas << "Google Maps: status '#{details[:business_status]}', tratar como excecao."
    end

    if details[:rating]
      pontos += (W::MAPS[:rating] * details[:rating].to_f / 5.0).round
    else
      @dados_nao_encontrados << 'rating'
    end
    indicadores[:rating] = details[:rating]

    pontos += avaliacoes_pontos(details[:user_ratings_total])
    indicadores[:user_ratings_total] = details[:user_ratings_total]

    completude = [details[:has_website], details[:has_phone], details[:has_opening_hours]].count(true)
    pontos += (W::MAPS[:completude] * completude / 3.0).round
    indicadores[:completude_sinais] = completude

    { pontos: pontos, indicadores: indicadores }
  end

  # Sem Place Details, ainda temos rating/user_ratings_total capturados na busca (Text Search) --
  # melhor um fallback parcial do que zerar o pilar inteiro por uma chamada de API que falhou.
  def maps_pillar_from_search_only
    pontos = 0
    pontos += (W::MAPS[:rating] * @result.rating.to_f / 5.0).round if @result.rating
    pontos += avaliacoes_pontos(@result.user_ratings_total)
    { pontos: pontos, indicadores: { presenca_confirmada: false, rating: @result.rating, user_ratings_total: @result.user_ratings_total } }
  end

  def avaliacoes_pontos(total)
    return 0 if total.blank? || total.zero?
    return (W::MAPS[:avaliacoes] * 0.4).round if total <= 10
    return (W::MAPS[:avaliacoes] * 0.7).round if total <= 50

    W::MAPS[:avaliacoes]
  end

  # ---- Instagram (25) ---------------------------------------------------------------------

  def instagram_pillar(scanner)
    instagram = scanner&.dig('instagram')
    unless instagram && instagram['followers'].to_i.positive?
      @dados_nao_encontrados << 'instagram'
      return { pontos: 0, indicadores: { perfil_encontrado: false } }
    end

    pontos = W::INSTAGRAM[:perfil_encontrado]
    pontos += faixa_pontos(instagram['followers'], W::INSTAGRAM[:seguidores], [500, 2000, 10_000, 50_000])
    pontos += faixa_pontos(instagram['posts'], W::INSTAGRAM[:posts], [10, 30, 100])

    indicadores = {
      perfil_encontrado: true,
      seguidores: instagram['followers'],
      posts: instagram['posts']
    }

    bio = instagram['bio']
    if bio.present?
      classificacao = Sales::Prospecting::BioClassifierService.call(bio)
      if classificacao
        pontos += W::INSTAGRAM[:bio] / 2 if classificacao[:clareza]
        pontos += W::INSTAGRAM[:bio] / 2 if classificacao[:profissionalismo]
        indicadores[:bio_clareza] = classificacao[:clareza]
        indicadores[:bio_profissionalismo] = classificacao[:profissionalismo]
      else
        @dados_nao_encontrados << 'bio_classificacao'
      end
    else
      @dados_nao_encontrados << 'bio'
    end

    { pontos: pontos, indicadores: indicadores }
  end

  # Distribui max_points entre faixas crescentes de volume (seguidores/posts) -- ultima faixa
  # (valor acima do maior limite) ganha o maximo.
  def faixa_pontos(valor, max_points, limites)
    return 0 if valor.blank? || valor.to_i.zero?

    posicao = limites.count { |limite| valor.to_i > limite }
    ((posicao + 1) * max_points / (limites.size + 1).to_f).round
  end

  # ---- ICP (15) ----------------------------------------------------------------------------

  def icp_pillar(details, scanner)
    business_type = @result.search&.business_type.to_s.downcase
    site = scanner&.dig('site') || {}
    texto_site = "#{site['title']} #{site['description']}".downcase

    indicadores = {}
    pontos = 0

    if business_type.present? && keywords_overlap?(business_type, texto_site, details&.dig(:primary_type))
      pontos += W::ICP[:segmento]
      indicadores[:segmento_confirmado] = true
    elsif business_type.present?
      pontos += (W::ICP[:segmento] * 0.4).round
      indicadores[:segmento_confirmado] = false
      @alertas << 'ICP: segmento buscado nao confirmado no site/categoria -- confirmar manualmente.'
    else
      @dados_nao_encontrados << 'segmento_busca'
    end

    b2b_keywords = %w[atacado distribuidor fornecedor industria fabricante revenda b2b franquia]
    if b2b_keywords.any? { |k| texto_site.include?(k) }
      pontos += W::ICP[:evidencia_b2b]
      indicadores[:evidencia_b2b] = true
    else
      indicadores[:evidencia_b2b] = false
    end

    if details&.dig(:primary_type).present?
      pontos += W::ICP[:categoria_google]
      indicadores[:categoria_google] = details[:primary_type]
    else
      @dados_nao_encontrados << 'categoria_google'
    end

    # CNAE fica de fora do v1 -- falta fonte de CNPJ a partir do lead (ver ScanWeights).
    { pontos: pontos, indicadores: indicadores }
  end

  def keywords_overlap?(business_type, texto_site, primary_type)
    tokens = business_type.split(/\s+/).reject { |t| t.length < 4 }
    return false if tokens.empty?

    tokens.any? { |t| texto_site.include?(t) || primary_type.to_s.downcase.tr('_', ' ').include?(t) }
  end
end
