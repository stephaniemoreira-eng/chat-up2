# SSOT §16.1/§28.14/§28.15/§28.32: "Agendado" só pode existir por reunião real -- confirmado,
# com event_id e agendado_em reais. A regra já vive na aplicação (StartSchedulingService,
# UpdateMeetingService); este constraint garante o mesmo no banco, cobrindo também console,
# scripts e qualquer outra via que não passe pelas validações do Rails (§30, defesa em
# profundidade).
class EnforceConfirmedCalendarForAgendado < OperationalEngine::Migration
  CONSTRAINT = 'chk_leads_agendado_requires_confirmed_calendar'.freeze

  def up
    execute <<~SQL
      ALTER TABLE leads ADD CONSTRAINT #{CONSTRAINT}
        CHECK (
          etapa_prospect <> 'agendado'
          OR (
            agendamento_status = 'confirmado'
            AND calendar_event_id IS NOT NULL
            AND agendado_em IS NOT NULL
          )
        );
    SQL
  end

  def down
    execute "ALTER TABLE leads DROP CONSTRAINT IF EXISTS #{CONSTRAINT}"
  end
end
