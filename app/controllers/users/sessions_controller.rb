class Users::SessionsController < Devise::Passwordless::SessionsController
  include VerifiesAltchaCaptcha

  def create
    if (self.resource = resource_class.find_for_authentication(email: create_params[:email]))
      send_magic_link(resource)
      if Devise.paranoid
        set_flash_message!(:notice, :magic_link_sent_paranoid)
      else
        set_flash_message!(:notice, :magic_link_sent)
      end
      redirect_to(after_magic_link_sent_path_for(resource), status: devise_redirect_status)
    else
      self.resource = resource_class.new(email: create_params[:email])
      set_flash_message!(:alert, :not_found_in_database)
      redirect_to new_session_path(resource_name), status: devise_redirect_status
    end
  end
end
