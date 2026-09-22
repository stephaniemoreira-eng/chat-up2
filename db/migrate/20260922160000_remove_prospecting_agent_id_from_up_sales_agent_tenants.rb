# Corrige uma redundância real introduzida na Fase 6 (peça 2, dispatcher): na hora de codar,
# não descobri que já existia UpSales::AgentSlot (agent_type: 'sdr') + UpSales::Agents::
# UpsertAgentService -- o mecanismo já estabelecido (Super Admin de configuração de agente,
# docs/fork/ADR-0004-up-sales-reskin.md) que cria o agente no up2-agents e guarda o
# up2_agents_agent_id sozinho, quando o slot "sdr" é ativado. `prospecting_agent_id` duplicava
# esse dado sem nenhum jeito de ser preenchido de verdade (nada escreve nele) -- nunca foi
# populado em nenhum ambiente real, seguro remover sem migração de dados.
#
# A partir de agora, UpSales::AgentTenant#dispatcher_ready? e OriginateConversationService lêem
# o id do agente de prospecção via account.up_sales_agent_slots (agent_type: 'sdr'), não mais
# desta coluna.
class RemoveProspectingAgentIdFromUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    remove_column :up_sales_agent_tenants, :prospecting_agent_id, :bigint
  end
end
