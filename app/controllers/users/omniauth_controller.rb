class Users::OmniauthController < Devise::OmniauthCallbacksController
  def google_oauth2
    auth = request.env["omniauth.auth"]

    @user = User.find_or_link_from_provider_data(auth, locale: session[:locale])

    if @user.nil?
      session[:pending_oauth_identity] = {
        provider: auth.provider,
        uid:      auth.uid,
        email:    auth.info.email,
        name:     auth.info.name,
        locale:   session[:locale] || I18n.default_locale.to_s
      }
      redirect_to new_oauth_consent_url and return
    end

    unless @user.persisted?
      flash[:error] = t("consents.google_sign_in_failed")
      redirect_to new_user_registration_url and return
    end

    sign_in @user
    set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?

    if @user.accepted_current_policies?
      redirect_to after_sign_in_path_for(@user)
    else
      redirect_to new_consent_url
    end
  end

  def failure
    flash[:error] = "There was a problem signing you in. Please register or try signing in later."
    redirect_to new_user_registration_url
  end
end
