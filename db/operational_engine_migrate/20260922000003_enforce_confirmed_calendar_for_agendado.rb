# §16.1/§21.2: o estado Agendado é permitido somente depois de o Calendar confirmar a reunião e
# devolver seu identificador real. A regra vive no banco do Engine para também cobrir scripts,
# console e qualquer integração que não passe pelas validações do Rails.
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
