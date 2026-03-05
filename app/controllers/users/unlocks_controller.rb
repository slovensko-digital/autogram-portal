class Users::UnlocksController < Devise::UnlocksController
  include VerifiesAltchaCaptcha
end
