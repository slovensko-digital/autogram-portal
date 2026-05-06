class ConsentsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :enforce_current_policy_consent

  def new
  end

  def create
    if params[:agree_to_policies] == "1"
      UserPolicyConsent.record_current_for(user: current_user, source: "re_consent", request: request)
      redirect_to after_sign_in_path_for(current_user), notice: t("consents.accepted")
    else
      flash.now[:alert] = t("consents.must_accept")
      render :new, status: :unprocessable_entity
    end
  end
end
