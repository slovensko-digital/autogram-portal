class Admin::TenantsController < Admin::BaseController
  before_action :set_tenant, only: [ :edit, :update, :add_member ]

  def index
    @tenants = Tenant.includes(:owners).left_joins(:memberships)
                     .select("tenants.*, COUNT(memberships.id) AS members_count")
                     .group("tenants.id")
                     .order(:name)
    @tenants = @tenants.where("tenants.name ILIKE :q OR tenants.id IN (SELECT memberships.tenant_id FROM memberships JOIN users ON users.id = memberships.user_id WHERE users.email ILIKE :q)", q: "%#{Tenant.sanitize_sql_like(params[:q])}%") if params[:q].present?
  end

  def new
    @tenant = Tenant.new(plan: :pro)
  end

  # Sets up an organization for a customer: the tenant and its first owner, who
  # is invited when the email has no account yet.
  def create
    @tenant = Tenant.new(tenant_params)
    @owner_email = params[:owner_email].to_s.strip.downcase
    return render_new_with_error(t("admin.tenants.create.owner_email_missing")) if @owner_email.blank?

    membership = ActiveRecord::Base.transaction do
      @tenant.save!
      @tenant.add_member!(User.find_or_invite!(@owner_email), role: :owner)
    end

    TenantMailer.with(membership: membership).invitation.deliver_later
    redirect_to edit_admin_tenant_path(@tenant), notice: t("admin.tenants.create.success", email: @owner_email)
  rescue ActiveRecord::RecordInvalid => e
    @tenant = Tenant.new(tenant_params) if @tenant.persisted?
    render_new_with_error(e.record.errors.full_messages.to_sentence)
  end

  def edit
    @memberships = @tenant.memberships.includes(:user).order(:created_at)
  end

  def update
    if @tenant.update(tenant_params)
      redirect_to admin_tenants_path, notice: t("admin.tenants.update.success")
    else
      @memberships = @tenant.memberships.includes(:user).order(:created_at)
      render :edit, status: :unprocessable_entity
    end
  end

  def add_member
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    return redirect_to edit_admin_tenant_path(@tenant), alert: t("admin.tenants.add_member.user_not_found") unless user

    @tenant.add_member!(user, role: params[:role].presence_in(Membership.roles.keys) || "member")
    redirect_to edit_admin_tenant_path(@tenant), notice: t("admin.tenants.add_member.success", email: user.email)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tenant_path(@tenant), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_tenant
    @tenant = Tenant.find(params[:id])
  end

  def render_new_with_error(message)
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  def tenant_params
    params.require(:tenant).permit(:name, :plan, features: [])
  end
end
