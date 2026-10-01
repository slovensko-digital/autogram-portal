class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :skip_policy_scope, if: -> { action_name == "index" }

  rescue_from Pundit::NotAuthorizedError, with: :render_admin_required

  private

  def authorize_admin!
    authorize :admin, :access?
  end

  def render_admin_required
    head :forbidden
  end
end
