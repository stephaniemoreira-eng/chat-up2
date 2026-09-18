# Normaliza um telefone no formato internacional do Google Places (ex.: "+55 13 3222-1234") para o
# E.164 estrito que Contact#phone_number exige (sem espacos/pontuacao). Fonte unica -- usado tanto
# na busca inicial (GooglePlacesSearchService) quanto no backfill do SCAN (ScanService), pra nao
# duplicar a regra nem deixar as duas divergirem.
module Sales::Prospecting::PhoneNormalizer
  def self.normalize(raw)
    return nil if raw.blank?

    digits = raw.gsub(/[^\d+]/, '')
    digits if digits.match?(/\A\+[1-9]\d{1,14}\z/)
  end
end
