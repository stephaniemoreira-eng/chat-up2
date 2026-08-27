# Promove contatos marcados com a label de Follow-up (importados via CSV nativo do Chatwoot,
# que ja aplica labels durante a propria importacao) a Sales::Lead no Kanban dedicado de
# Follow-up, e distribui -- cada lead novo, e qualquer lead ainda sem responsavel -- entre os
# membros do Team (nativo) de vendedores, por rodizio balanceado: quem tem menos leads
# atribuidos no momento recebe o proximo. Sem cursor persistido -- o "estado" e sempre
# recalculado a partir da contagem atual, entao nao ha nada pra corrigir se alguem entra ou sai
# do time.
#
# Roda automaticamente (Sales::FollowUp::SyncJob, cron) e sob demanda (botao "Distribuir agora"
# na tela de Follow-up) -- as duas chamam este mesmo servico. Ver
# docs/fork/ADR-0004-up-sales-reskin.md.
class Sales::FollowUp::SyncService
  DEFAULT_LABEL = 'follow-up'.freeze

  class NotConfiguredError < StandardError; end

  def self.perform(account:)
    new(account: account).perform
  end

  def initialize(account:)
    @account = account
  end

  def perform
    raise NotConfiguredError unless configured?

    { created: promote_new_contacts, assigned: assign_unassigned_leads }
  end

  private

  attr_reader :account

  def configured?
    pipeline.present? && team.present?
  end

  def pipeline
    @pipeline ||= account.sales_pipelines.find_by(id: account.follow_up_pipeline_id)
  end

  def team
    @team ||= account.teams.find_by(id: account.follow_up_team_id)
  end

  def label
    account.follow_up_label.presence || DEFAULT_LABEL
  end

  def default_stage
    pipeline.stages.first
  end

  def promote_new_contacts
    already_promoted_ids = pipeline.leads.pluck(:contact_id)
    candidates = account.contacts.tagged_with(label, on: :labels).where.not(id: already_promoted_ids)

    candidates.find_each.count do |contact|
      account.sales_leads.create!(
        contact: contact,
        pipeline: pipeline,
        stage: default_stage,
        title: contact.name,
        source: 'follow_up_import'
      )
    end
  end

  def assign_unassigned_leads
    pipeline.leads.where(assignee_id: nil).find_each.count do |lead|
      vendedor_id = next_vendedor_id
      next false if vendedor_id.blank?

      lead.update!(assignee_id: vendedor_id)
    end
  end

  def next_vendedor_id
    member_ids = team.members.ids
    return nil if member_ids.empty?

    load_counts = Sales::Lead.where(sales_pipeline_id: pipeline.id, assignee_id: member_ids).group(:assignee_id).count
    member_ids.min_by { |id| load_counts[id] || 0 }
  end
end
