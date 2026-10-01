class Api::V1::HelloController < ApiController
  skip_before_action :authenticate_tenant!, only: [ :show ]

  def show
    skip_authorization
    render json: { message: "Hello, World!" }
  end

  def show_auth
    authorize [ :api, :v1, :hello ]
    render json: { message: "Hello, #{ current_tenant.id }!" }
  end
end
