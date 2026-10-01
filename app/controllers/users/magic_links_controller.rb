class Users::MagicLinksController < Devise::MagicLinksController
  before_action :skip_authorization, only: [ :show ]
end
