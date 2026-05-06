class OauthConsentsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :enforce_current_policy_consent

  before_action :load_pending_oauth_data

  def new
  end

  def create
    unless params[:agree_to_policies] == "1"
      flash.now[:alert] = t("consents.must_accept_to_register")
      render :new, status: :unprocessable_entity
      return
    end

    user = User.create!(
      email:            @pending[:email],
      name:             @pending[:name],
      confirmed_at:     Time.current,
      locale:           @pending[:locale],
      agree_to_policies: true
    )
    user.identities.create!(provider: @pending[:provider], uid: @pending[:uid])
    UserPolicyConsent.record_current_for(user: user, source: "oauth_signup", request: request)

    session.delete(:pending_oauth_identity)

    sign_in user
    flash[:notice] = t("devise.omniauth_callbacks.success", kind: "Google")
    redirect_to after_sign_in_path_for(user)
  end

  private

  def load_pending_oauth_data
    data = session[:pending_oauth_identity]

    unless data.present?
      redirect_to new_user_registration_url and return
    end

    @pending = data.with_indifferent_access
  end
end
