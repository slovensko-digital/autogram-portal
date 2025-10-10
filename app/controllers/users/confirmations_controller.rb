class Users::ConfirmationsController < Devise::ConfirmationsController
  def after_confirmation_path_for(resource_name, resource)
    unless signed_in?(resource_name)
      sign_in(resource)
    end

    signed_in_root_path(resource)
  end
end