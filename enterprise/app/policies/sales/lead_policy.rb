class Sales::LeadPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  def move?
    true
  end

  def link_conversation?
    true
  end

  def unlink_conversation?
    true
  end

  def timeline?
    true
  end

  def update_summary?
    true
  end

  def register_callback_realizado?
    true
  end

  def register_no_show?
    true
  end

  def set_propensao?
    true
  end

  def register_resultado_comercial?
    true
  end

  # CP-05: mesmo escopo das demais ações Comerciais (RISK-025-01 -- o SSOT não congela uma matriz
  # RBAC; nenhuma regra de cargo nova é inventada aqui).
  def advance_etapa_comercial?
    true
  end

  def remove_no_show?
    true
  end

  def assumir?
    true
  end

  def devolver?
    true
  end

  def search?
    true
  end

  def create_leads?
    true
  end

  def sync?
    true
  end

  def summary?
    true
  end
end
