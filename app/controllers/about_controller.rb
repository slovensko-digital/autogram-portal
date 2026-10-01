class AboutController < ApplicationController
  before_action :skip_authorization, :skip_policy_scope, only: [ :index ]

  def index
    @current_user = current_user
  end
end
