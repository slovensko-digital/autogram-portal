class Users::RegistrationsController < Devise::RegistrationsController
  include VerifiesAltchaCaptcha

  before_action :configure_permitted_parameters

  def destroy
    expected_phrase = I18n.t("devise.registrations.edit.delete_confirmation_phrase")
    provided_phrase = params[:delete_confirmation].to_s.strip

    if provided_phrase != expected_phrase
      redirect_to edit_user_registration_path, alert: t("devise.registrations.edit.delete_confirmation_mismatch")
      return
    end

    resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
    resource.destroy
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    respond_with_navigational(resource) { redirect_to after_sign_out_path_for(resource_name) }
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name, :api_token_public_key ])
  end

  def update_resource(resource, params)
    params = params.except(:current_password, :password, :password_confirmation)

    resource.update(params)
  end

  def after_update_path_for(resource)
    edit_user_registration_path
  end
end
