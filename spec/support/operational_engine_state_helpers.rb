# CP-04 (P2-017-01, P2-018-01, P2-023-01): estados de compromisso sempre COMPLETOS, como o SSOT os
# define (§16.1, §16.2, §16.4) -- nunca "agendamento_status: 'confirmado'" solto. A constraint
# chk_leads_confirmado_requires_real_meeting recusa o estado incompleto no banco.
module OperationalEngineStateHelpers
  def confirmed_meeting_attributes(event_id: 'evt_confirmado', at: Time.current.change(usec: 0))
    {
      agendamento_status: 'confirmado', calendar_event_id: event_id, agendado_em: at,
      etapa_prospect: 'agendado', qualificacao_status: 'qualificado'
    }
  end

  def pending_callback_attributes
    {
      agendamento_status: 'callback_registrado', etapa_prospect: 'qualificado',
      qualificacao_status: 'qualificado', etapa_comercial: 'oportunidade'
    }
  end
end

RSpec.configure do |config|
  config.include OperationalEngineStateHelpers
end
