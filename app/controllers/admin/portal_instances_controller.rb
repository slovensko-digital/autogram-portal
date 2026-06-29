class Admin::PortalInstancesController < Admin::BaseController
  before_action :set_portal_instance, only: [ :edit, :update, :verify, :revoke ]

  def index
    @portal_instances = PortalInstance.order(:name)
  end

  def new
    @portal_instance = PortalInstance.new(status: "verified")
  end

  def create
    @portal_instance = PortalInstance.new(portal_instance_params)

    if @portal_instance.save
      redirect_to admin_portal_instances_path, notice: t("admin.portal_instances.create.success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @portal_instance.update(portal_instance_params)
      redirect_to admin_portal_instances_path, notice: t("admin.portal_instances.update.success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def verify
    @portal_instance.update!(status: "verified", last_verified_at: Time.current)
    redirect_to admin_portal_instances_path, notice: t("admin.portal_instances.verify.success")
  end

  def revoke
    @portal_instance.update!(status: "revoked")
    redirect_to admin_portal_instances_path, notice: t("admin.portal_instances.revoke.success")
  end

  private

  def set_portal_instance
    @portal_instance = PortalInstance.find_by!(uuid: params[:id])
  end

  def portal_instance_params
    params.require(:portal_instance).permit(
      :name,
      :base_url,
      :issuer,
      :public_key_pem,
      :status,
      :outbound_kid,
      allowed_email_domains: []
    )
  end
end
