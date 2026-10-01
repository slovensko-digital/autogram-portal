class Api::V1::HelloPolicy < Api::V1::ApplicationPolicy
  def show_auth?
    authenticated?
  end
end
