class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_permitted_parameters

  def destroy
    raise NotImplementedError
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def update_resource(resource, params)
    params = params.except(:current_password, :password, :password_confirmation)

    resource.update(params)
  end

  def after_update_path_for(resource)
    edit_user_registration_path
  end
end