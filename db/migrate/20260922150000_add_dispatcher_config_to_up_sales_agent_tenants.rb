# SSOT §10.5/Fase 6: o dispatcher precisa saber, por tenant, qual inbox WhatsApp usar pra
# primeira abordagem e qual agente do up2-agents é "a Lavínia" desse tenant (o Agent de lá não
# tem um campo "kind" distinguindo prospecção/follow-up/secretária -- confirmado lendo o schema
# do up2-agents). Os dois são configuração manual (mesmo padrão de calendar_integration_instance_id
# e api_key nesta mesma tabela), não auto-detectados: já houve mais de um inbox/ambiente ambíguo
# neste projeto, não vale arriscar adivinhar.
#
# whatsapp_inbox_id tem FK de verdade (inboxes é nativo, mesmo banco). prospecting_agent_id não
# tem -- é o id numérico do Agent no banco do up2-agents, um sistema totalmente separado.
class AddDispatcherConfigToUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    add_reference :up_sales_agent_tenants, :whatsapp_inbox, foreign_key: { to_table: :inboxes }, null: true
    add_column :up_sales_agent_tenants, :prospecting_agent_id, :bigint
  end
end
