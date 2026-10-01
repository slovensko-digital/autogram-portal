class RootController < ApplicationController
  before_action :skip_authorization, :skip_policy_scope, only: [ :index ]

  def index
    return redirect_to about_index_path unless current_user

    redirect_to dashboard_path
  end
end
