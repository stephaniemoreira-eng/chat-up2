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
