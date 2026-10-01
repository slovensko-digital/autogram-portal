class Users::UnlocksController < Devise::UnlocksController
  include VerifiesAltchaCaptcha

  before_action :skip_authorization, only: [ :new, :create, :show ]
end
