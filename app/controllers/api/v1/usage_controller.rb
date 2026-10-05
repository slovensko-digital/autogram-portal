class Api::V1::UsageController < ApiController
  def show
    authorize [ :api, :v1, :usage ]
    @tenant = current_tenant
    @period = Time.current.all_month
  end
end
