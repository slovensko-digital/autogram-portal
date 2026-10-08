class HowToSignController < ApplicationController
  before_action :skip_authorization, :skip_policy_scope, only: [ :index ]

  def index
  end
end
