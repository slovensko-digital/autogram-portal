class Admin::TenantsController < Admin::BaseController
  # The usage sorts list the biggest consumers in the selected month first.
  ORDERS = {
    "name" => [ :name, :id ],
    "id_asc" => [ :id ],
    "id_desc" => [ { id: :desc } ],
    "signature_requests" => [ Arel.sql("signature_requests_usage DESC"), :name, :id ],
    "timestamps" => [ Arel.sql("timestamps_usage DESC"), :name, :id ]
  }.freeze

  before_action :set_tenant, only: [ :edit, :update, :add_member ]

  def index
    @plan = params[:plan].presence_in(Tenant.plans.keys)
    @sort = params[:sort].presence_in(ORDERS.keys) || "name"
    @usage_month = usage_month

    tenants = params[:q].present? ? search_tenants(params[:q]) : Tenant.all
    tenants = tenants.where(plan: @plan) if @plan
    @tenants = tenants.includes(:owners).left_joins(:memberships)
                      .select("tenants.*", "COUNT(memberships.id) AS members_count", *monthly_usage_columns(@usage_month))
                      .group("tenants.id")
                      .order(*ORDERS.fetch(@sort))
                      .load
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
      @tenant.memberships.create!(user: User.find_or_invite!(@owner_email), role: :owner)
    end

    TenantMailer.with(membership: membership).invitation.deliver_later
    redirect_to edit_admin_tenant_path(@tenant), notice: t("admin.tenants.create.success", email: @owner_email)
  rescue ActiveRecord::RecordInvalid => e
    render_new_with_error(e.record.errors.full_messages.to_sentence)
  end

  def edit
    @memberships = @tenant.memberships.includes(:user).order(:created_at)
    set_usage
  end

  def update
    if @tenant.update(tenant_params)
      redirect_to admin_tenants_path, notice: t("admin.tenants.update.success")
    else
      @memberships = @tenant.memberships.includes(:user).order(:created_at)
      set_usage
      render :edit, status: :unprocessable_entity
    end
  end

  def add_member
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    return redirect_to edit_admin_tenant_path(@tenant), alert: t("admin.tenants.add_member.user_not_found") unless user

    @tenant.memberships.create!(user: user, role: params[:role].presence_in(Membership.roles.keys) || "member")
    redirect_to edit_admin_tenant_path(@tenant), notice: t("admin.tenants.add_member.success", email: user.email)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tenant_path(@tenant), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_tenant
    @tenant = Tenant.find(params[:id])
  end

  def search_tenants(query)
    pattern = "%#{Tenant.sanitize_sql_like(query)}%"
    member_tenant_ids = Membership.joins(:user).where("users.email ILIKE ?", pattern).select(:tenant_id)
    Tenant.where("tenants.name ILIKE ?", pattern).or(Tenant.where(id: member_tenant_ids))
  end

  # The usage of every monthly limit (signature_requests_usage, timestamps_usage) in the month.
  def monthly_usage_columns(month)
    Tenant::Usage::MONTHLY_LIMIT_KINDS.map do |limit, kind|
      usage = UsageRecord.where(kind: kind).in_period(month.in_time_zone.all_month).where("usage_records.tenant_id = tenants.id")
      "(#{usage.select("COALESCE(SUM(usage_records.quantity), 0)").to_sql}) AS #{limit}_usage"
    end
  end

  # Monthly usage by kind and source, the basis for billing the PRO plan.
  def set_usage
    @usage_month = usage_month
    @usage_by_kind_and_source = @tenant.usage_records.in_period(@usage_month.in_time_zone.all_month).group(:kind, :source).sum(:quantity)
  end

  # The first day of the requested month. Query it as month.in_time_zone.all_month: a Date range ends at midnight of the last day.
  def usage_month
    Date.strptime(params[:month].to_s, "%Y-%m")
  rescue Date::Error
    Date.current.beginning_of_month
  end

  def render_new_with_error(message)
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  def tenant_params
    params.require(:tenant).permit(:name, :plan, features: [])
  end
end
