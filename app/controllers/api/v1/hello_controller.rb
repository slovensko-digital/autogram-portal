class Api::V1::HelloController < ApiController
  skip_before_action :authenticate_tenant!, only: [ :show ]

  def show
    render json: { message: "Hello, World!" }
  end

  def show_auth
    render json: { message: "Hello, #{current_tenant.id}!" }
  end
end
