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

  # CP-05 (P2-025-01; SSOT §17.2, §8.4): oportunidade Comercial COMPLETA, como o handoff real a
  # deixa -- Prospect Qualificado, frente Comercial, humano responsável, recovery encerrada. Nunca
  # "etapa_comercial: 'oportunidade'" solto sobre um lead em Backlog.
  def comercial_opportunity_attributes(etapa_comercial: 'oportunidade', responsavel_atual_id: 77)
    {
      etapa_prospect: 'qualificado', qualificacao_status: 'qualificado', qualificado_em: 2.days.ago.change(usec: 0),
      frente_operacional: 'comercial', modo_atendimento: 'humano', responsavel_atual_id: responsavel_atual_id,
      motivo_handoff: 'avanco_comercial', etapa_comercial: etapa_comercial, resultado_comercial: 'em_aberto',
      recuperacao_status: 'inativa', proxima_recuperacao_em: nil, aguardando_resposta: false
    }
  end
end

RSpec.configure do |config|
  config.include OperationalEngineStateHelpers
end
