# CP-05 (P1-023-03, P1-025-02; SSOT §4 "Etapa Comercial: Supabase, refletida no UpSales", §8.4,
# §21.2 "movimentações comerciais permitidas" / "transições protegidas não podem ser contornadas
# por drag simples", §30, §28.39).
#
# A "movimentação comercial permitida" como ação Engine-controlled: o Engine valida a transição
# (máquina mínima do §8.4), persiste etapa + evento e só então a projeção move o card. É o destino
# de um drag humano num card Comercial gerido pelo Engine (Api::V1::Accounts::Sales::LeadsController#move)
# -- o card nunca muda de coluna só no CRM.
#
# Só Oportunidade → Em acompanhamento passa por aqui. Ganho/Perdido têm ação própria
# (OperationalEngine::RegisterResultadoComercialService: ganho_em, relação, encerramento, motivo da
# perda) e nunca nascem de um drag; qualquer outra transição (inclusive voltar etapa) é recusada.
# Pedir a etapa em que o lead já está é no-op (repara projeção pendente, se houver).
module OperationalEngine
  class AdvanceEtapaComercialService
    ETAPAS_VIA_MOVIMENTACAO = %w[em_acompanhamento].freeze

    def self.call!(lead:, etapa:, user_id:)
      new(lead, etapa, user_id).call!
    end

    def initialize(lead, etapa, user_id)
      @lead = lead
      @etapa = etapa
      @user_id = user_id
    end

    def call!
      @lead.with_lock do
        next if @lead.etapa_comercial == @etapa

        validate!
        previous = @lead.etapa_comercial
        @lead.update!(etapa_comercial: @etapa)
        write_event(previous)
        OperationalEngine::ProjectionReconciler.request!(@lead, motivo: 'etapa_comercial_alterada')
      end

      OperationalEngine::ProjectionReconciler.flush(@lead)
      @lead
    end

    private

    def validate!
      unless ETAPAS_VIA_MOVIMENTACAO.include?(@etapa)
        raise OperationalEngine::ComercialActionGuard::InvalidContextError,
              "#{@etapa.presence || 'etapa vazia'} não é uma movimentação Comercial permitida por arraste -- use a ação própria"
      end

      OperationalEngine::ComercialActionGuard.ensure_transicao!(@lead, para: @etapa)
    end

    def write_event(previous)
      OperationalEngine::LeadEvent.create!(
        lead: @lead, event_type: 'etapa_alterada', source: 'human',
        metadata: { funil: 'comercial', de: previous, para: @etapa, motivo: 'movimentacao_comercial',
                    responsavel_atual_id: @user_id, correlation_id: SecureRandom.uuid }
      )
    end
  end
end
