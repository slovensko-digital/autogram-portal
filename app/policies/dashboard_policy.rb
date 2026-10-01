class DashboardPolicy < ApplicationPolicy
  def index?
    in_tenant?
  end
end
