# frozen_string_literal: true

# Raiz explícita do namespace Enterprise. Sem este arquivo, o carregamento preguiçoso em test
# não consegue materializar `UpSales` antes de resolver classes como UpSales::AgentTenant.
module UpSales
end