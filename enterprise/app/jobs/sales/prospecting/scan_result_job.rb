# Roda o SCAN v1 (Sales::Prospecting::ScanService) para um resultado de prospeccao, em background
# -- as chamadas (PageSpeed, Place Details, up2-scanner, IA) sao de rede e nao podem travar a
# criacao do lead. Enfileirado por CreateLeadsFromResultsService quando a conta tem `sales_scan`
# habilitada (opt-in, hoje so a UP2).
class Sales::Prospecting::ScanResultJob < ApplicationJob
  queue_as :low

  def perform(result_id)
    result = Sales::ProspectingResult.find_by(id: result_id)
    return if result.nil?

    Sales::Prospecting::ScanService.call(result)
  end
end
