# S-5/S-4 (plano do Marco 1, I-3): gera ou rotaciona o `engine_api_key` de um UpSales::AgentTenant
# -- o segredo que o up2-agents apresenta ao chamar de volta as rotas
# operational_engine/{tools,actions,snapshot} deste repositório (Contrato B/S-4). `has_secure_token`
# só preenche sozinho na criação do registro; um tenant criado antes da coluna existir fica com
# `engine_api_key` nulo até rodar isto. Sem UI ainda pra isso -- só este comando, uma vez por
# conta, e a chave é colada manualmente no ToolDefinitions do up2-agents pelo Igor (I-3).
namespace :up_sales do
  desc 'Gera (ou rotaciona) o engine_api_key de uma conta. Uso: rake up_sales:generate_engine_api_key[account_id]'
  task :generate_engine_api_key, [:account_id] => :environment do |_t, args|
    abort 'Uso: rake up_sales:generate_engine_api_key[account_id]' if args[:account_id].blank?

    tenant = UpSales::AgentTenant.find_by(account_id: args[:account_id])
    if tenant.nil?
      abort "Nenhum UpSales::AgentTenant para account_id=#{args[:account_id]} -- crie o tenant antes (painel Super Admin)."
    end

    rotating = tenant.engine_api_key.present?
    tenant.regenerate_engine_api_key

    puts "#{rotating ? 'Rotacionada' : 'Gerada'} para account_id=#{args[:account_id]} (agents_tenant_id=#{tenant.agents_tenant_id})."
    puts "engine_api_key: #{tenant.engine_api_key}"
    if rotating
      puts 'ATENÇÃO: a chave antiga parou de funcionar -- atualize o ToolDefinitions do up2-agents também.'
    else
      puts 'Cole esta chave no ToolDefinitions do up2-agents (I-3) como Bearer token.'
    end
  end
end
