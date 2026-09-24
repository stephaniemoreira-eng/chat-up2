# CP-16A -- decisões de negócio da Stéphanie em 24/09/2026 (lacunas do SSOT MVP01), configuradas POR
# CONTA no Super Admin de configuração de agente (ADR-0004), mesma tabela do resto da configuração
# do tenant Up Sales:
#
# - P2-VAL-16 (responsável Comercial do handoff pedido pela Lavínia = "DANILO"):
#   `commercial_responsible_user_id` -- o usuário (da própria conta, validado no modelo) que vira
#   responsavel_atual_id quando a Lavínia faz o handoff e nenhum humano já é o responsável. Nulo =
#   comportamento anterior (responsável pendente). FK com nullify: apagar o usuário volta a conta
#   para "pendente" em vez de apontar para um id inexistente. Nada de nome/ID fixo no código.
# - P2-VAL-17 (texto do e-mail da 3ª tentativa de recovery "SER AJUSTÁVEL"):
#   `recovery_email_subject` / `recovery_email_body` -- modelo com placeholders; vazios = o modelo
#   neutro do CP-13 continua valendo.
class AddBusinessDecisionsConfigToUpSalesAgentTenants < ActiveRecord::Migration[7.1]
  def change
    add_reference :up_sales_agent_tenants, :commercial_responsible_user, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_column :up_sales_agent_tenants, :recovery_email_subject, :string
    add_column :up_sales_agent_tenants, :recovery_email_body, :text
  end
end
