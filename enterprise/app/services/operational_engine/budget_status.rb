# CP-14 (P1-VAL-13; SSOT §6.2 `orcamento_status`, §7.3, §12.4, §14.1, §14.3, §17.1, testes 28.12/28.13).
# Transições de `orcamento_status` depois do início do dimensionamento (StartBudgetService grava
# `em_dimensionamento`). Máquina implícita do SSOT: nao_solicitado → em_dimensionamento → informado |
# personalizado. Nunca rebaixa: `personalizado` é final; `informado` só avança para `personalizado`.
#
# Como a Lavínia sinaliza cada caso (Prompt V1.0 é artefato controlado -- nenhum campo novo):
# - PERSONALIZADO: `motivo_handoff = orcamento_personalizado` na saída estruturada (§12.4/§17.1),
#   venha com `acao_sugerida = handoff_comercial` ou com a ida direta para agenda do Prompt §15.4. O
#   HandoffToCommercialService usa a mesma transição quando o handoff tem esse motivo.
# - INFORMADO: o Prompt não pede à Lavínia nenhum campo de "preço informado". O sinal factual que
#   existe é a própria `mensagem_resposta` que sai para o lead (turno conversacional, em que o texto do
#   modelo é o texto enviado). O Engine só RECONHECE que um dos dois valores diretos autorizados do
#   §14.3 foi dito dentro de uma rota de orçamento ativa (§14.1) -- nunca calcula, escolhe ou infere
#   preço a partir de volume/frequência (§14.3 proíbe preço por kg/inferência).
#
# Chamado SEMPRE dentro do `lead.with_lock` de quem muda o lead (estado relido, §23.2); a idempotência
# por turno fica com TurnIdempotency no controller, e o replay da mesma transição é no-op aqui.
module OperationalEngine
  module BudgetStatus
    # §14.3: os únicos valores diretos autorizados, como a Lavínia os escreve ("R$ 1.800,00").
    DIRECT_PRICES = {
      'R$ 1.800,00' => /R\$\s*1\.?800(?:,00)?(?![.,]?\d)/,
      'R$ 2.500,00' => /R\$\s*2\.?500(?:,00)?(?![.,]?\d)/
    }.freeze
    # Só nestes o texto do modelo é o texto enviado; nos demais a resposta pública sai da
    # finalização pós-despacho (up2-agents runtime), não de `mensagem_resposta`.
    CONVERSATIONAL_ACOES = %w[nenhuma continuar_conversa].freeze
    INFORMADO_FROM = %w[nao_solicitado em_dimensionamento].freeze
    PERSONALIZADO_FROM = %w[nao_solicitado em_dimensionamento informado].freeze

    module_function

    # Commit do turno (ApplyStructuredOutputService). Personalizado vence um valor no mesmo turno:
    # caso fora da faixa conhecida não pode terminar como preço informado (28.13).
    def apply_turn!(lead, saida)
      return false if blocked?(lead)
      return personalizar!(lead, motivo: 'motivo_handoff_orcamento_personalizado') if saida['motivo_handoff'] == 'orcamento_personalizado'

      valor = informed_direct_price(lead, saida)
      valor ? informar!(lead, valor: valor, motivo: 'preco_direto_informado') : false
    end

    def informar!(lead, valor:, motivo:)
      return false unless INFORMADO_FROM.include?(lead.orcamento_status)

      transition!(lead, 'informado', 'orcamento_informado', motivo: motivo, valor_informado: valor)
    end

    def personalizar!(lead, motivo:)
      return false unless PERSONALIZADO_FROM.include?(lead.orcamento_status)

      transition!(lead, 'personalizado', 'orcamento_personalizado', motivo: motivo)
    end

    # Rota de orçamento ativa (§14.1): o dimensionamento já começou ou o lead pediu preço/orçamento
    # (fato extraído neste turno ou antes). Volume/frequência/localização sozinhos não contam.
    def informed_direct_price(lead, saida)
      return unless CONVERSATIONAL_ACOES.include?(saida['acao_sugerida'])
      return unless lead.orcamento_status_em_dimensionamento? || lead.intencao_comercial_quer_orcamento?

      direct_price_in(saida['mensagem_resposta'])
    end

    def direct_price_in(text)
      return unless text.is_a?(String)

      DIRECT_PRICES.find { |_valor, pattern| text.match?(pattern) }&.first
    end

    def blocked?(lead)
      lead.modo_atendimento_humano? || lead.nao_contatar? || lead.lead_status_encerrado?
    end

    def transition!(lead, para, event_type, motivo:, **extra)
      de = lead.orcamento_status
      lead.update!(orcamento_status: para)
      OperationalEngine::LeadEvent.create!(
        lead: lead, event_type: event_type, source: 'lavinia',
        metadata: { de: de, para: para, motivo: motivo, **extra, correlation_id: SecureRandom.uuid }
      )
      true
    end
  end
end
