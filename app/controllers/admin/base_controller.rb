class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  private

  def authorize_admin!
    head :forbidden unless current_user&.admin?
  end
end
