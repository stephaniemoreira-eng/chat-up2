# S-5/S-4 (plano do Marco 1, I-3): gera ou rotaciona o `engine_api_key` de um UpSales::AgentTenant
# -- o segredo que o up2-agents apresenta ao chamar de volta as rotas
# operational_engine/{tools,actions,snapshot} deste repositório (Contrato B/S-4). Um tenant novo
# não tem chave até rodar isto. CP-12 (P1-VAL-10): aqui fica só o SHA-256 da chave.
#
# CP-07 (P1-020-01/P2-020-01): a chave vai direto pro Vault do up2-agents
# (UpSales::Agents::ProvisionEngineApiKeyService) -- nada de colar em ToolDefinitions, e o segredo
# nunca aparece no stdout desta task (§29.1: stdout de task administrativa costuma virar log).
namespace :up_sales do
  desc 'Gera (ou rotaciona) o engine_api_key de uma conta e provisiona no Vault do up2-agents. Uso: rake up_sales:generate_engine_api_key[account_id]'
  task :generate_engine_api_key, [:account_id] => :environment do |_t, args|
    abort 'Uso: rake up_sales:generate_engine_api_key[account_id]' if args[:account_id].blank?

    tenant = UpSales::AgentTenant.find_by(account_id: args[:account_id])
    if tenant.nil?
      abort "Nenhum UpSales::AgentTenant para account_id=#{args[:account_id]} -- crie o tenant antes (painel Super Admin)."
    end

    begin
      result = UpSales::Agents::ProvisionEngineApiKeyService.new(agent_tenant: tenant).perform
    rescue UpSales::Agents::ProvisionEngineApiKeyService::ProvisionError => e
      abort "Falhou, nada foi alterado no chat-up2: #{e.message}"
    end

    puts "#{result[:rotated] ? 'Rotacionada' : 'Gerada'} para account_id=#{result[:account_id]} " \
         "(agents_tenant_id=#{tenant.agents_tenant_id}) e provisionada no Vault do up2-agents " \
         "(entrada #{result[:vault_entry_id]}, tipo operational_engine)."
    puts 'A chave não é exibida. Confira o health do Operational Engine no up2-agents.'
  end
end
