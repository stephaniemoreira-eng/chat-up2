# CP-04 (P1-023-01, P2-017-01/P2-018-01; SSOT §16.1, §16.4, §28.14, §28.29).
#
# A constraint anterior (chk_leads_agendado_requires_confirmed_calendar) exigia agendamento_status
# = 'confirmado' PARA SEMPRE em Agendado -- o que tornava impossível registrar uma reunião
# cancelada sem regredir a etapa (proibido pelo §28.29). Ela misturava duas regras:
#
# 1. chk_leads_agendado_requires_real_meeting -- Agendado só existe com prova de reunião real
#    (calendar_event_id + agendado_em, que só o caminho de sucesso do Calendar preenche). Depois
#    de cancelada, a reunião continua tendo existido: a etapa pode permanecer Agendado.
# 2. chk_leads_confirmado_requires_real_meeting -- agendamento_status='confirmado' também exige a
#    mesma prova (nenhuma fixture/console/script consegue "confirmar" sem Calendar real).
#
# A (2) entra NOT VALID de propósito (RISK-023-01): passa a valer para toda escrita nova sem exigir
# que linhas históricas já estejam saneadas -- o preflight/saneamento em ambiente com dados é
# pré-requisito do VALIDATE CONSTRAINT, fora desta migration. A (1) é mais frouxa que a anterior e
# por isso é validada na hora.
class SplitAgendadoConstraint < OperationalEngine::Migration
  OLD = 'chk_leads_agendado_requires_confirmed_calendar'.freeze
  AGENDADO = 'chk_leads_agendado_requires_real_meeting'.freeze
  CONFIRMADO = 'chk_leads_confirmado_requires_real_meeting'.freeze

  def up
    execute "ALTER TABLE leads DROP CONSTRAINT IF EXISTS #{OLD}"
    execute <<~SQL
      ALTER TABLE leads ADD CONSTRAINT #{AGENDADO}
        CHECK (etapa_prospect <> 'agendado' OR (calendar_event_id IS NOT NULL AND agendado_em IS NOT NULL));
    SQL
    execute <<~SQL
      ALTER TABLE leads ADD CONSTRAINT #{CONFIRMADO}
        CHECK (agendamento_status <> 'confirmado' OR (calendar_event_id IS NOT NULL AND agendado_em IS NOT NULL)) NOT VALID;
    SQL
  end

  def down
    execute "ALTER TABLE leads DROP CONSTRAINT IF EXISTS #{CONFIRMADO}"
    execute "ALTER TABLE leads DROP CONSTRAINT IF EXISTS #{AGENDADO}"
    # NOT VALID: linhas criadas sob a regra nova (reunião cancelada em Agendado) não podem impedir
    # o rollback.
    execute <<~SQL
      ALTER TABLE leads ADD CONSTRAINT #{OLD}
        CHECK (
          etapa_prospect <> 'agendado'
          OR (agendamento_status = 'confirmado' AND calendar_event_id IS NOT NULL AND agendado_em IS NOT NULL)
        ) NOT VALID;
    SQL
  end
end
