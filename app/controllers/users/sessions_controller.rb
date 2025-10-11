class Users::SessionsController < Devise::Passwordless::SessionsController
  def create
    if (self.resource = resource_class.find_for_authentication(email: create_params[:email]))
      send_magic_link(resource)
      if Devise.paranoid
        set_flash_message!(:notice, :magic_link_sent_paranoid)
      else
        set_flash_message!(:notice, :magic_link_sent)
      end
    else
      # Create new user and send confirmation email
      self.resource = resource_class.new(create_params)
      if resource.save
        resource.send_confirmation_instructions
        if Devise.paranoid
          set_flash_message!(:notice, :magic_link_sent_paranoid)
        else
          set_flash_message!(:notice, :signed_up_but_unconfirmed)
        end
      else
        clean_up_passwords resource
        set_minimum_password_length
        respond_with resource
        return
      end
    end

    redirect_to(after_magic_link_sent_path_for(resource), status: devise_redirect_status)
  end
end