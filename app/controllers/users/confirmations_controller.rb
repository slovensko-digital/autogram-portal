class Users::ConfirmationsController < Devise::ConfirmationsController
  include VerifiesAltchaCaptcha

  before_action :skip_authorization, only: [ :new, :create, :show ]

  def after_confirmation_path_for(resource_name, resource)
    unless signed_in?(resource_name)
      sign_in(resource)
    end

    signed_in_root_path(resource)
  end
end
