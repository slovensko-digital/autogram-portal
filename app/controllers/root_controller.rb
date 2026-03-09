class RootController < ApplicationController
  def index
    return redirect_to about_index_path unless current_user

    redirect_to dashboard_path
  end
end
