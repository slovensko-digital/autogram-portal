require "test_helper"

class Admin::TenantsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update_columns(email: "admin@example.com", confirmed_at: Time.current, features: [ "admin" ])
    @tenant = tenants(:two)
  end

  test "admin changes plan and features of a tenant" do
    sign_in @admin

    patch admin_tenant_path(@tenant), params: { tenant: { name: "Firma s.r.o.", plan: "pro", features: [ "", "api", "archivation" ] } }

    assert_redirected_to admin_tenants_path
    @tenant.reload
    assert @tenant.pro?
    assert_equal "Firma s.r.o.", @tenant.name
    assert_equal [ "api", "archivation" ], @tenant.features
  end

  test "admin can clear all features" do
    @tenant.update!(features: [ "api" ])
    sign_in @admin

    patch admin_tenant_path(@tenant), params: { tenant: { features: [ "" ] } }

    assert_empty @tenant.reload.features
  end

  test "admin adds an existing user to a pro tenant" do
    @tenant.update!(plan: :pro)
    sign_in @admin

    post add_member_admin_tenant_path(@tenant), params: { email: @admin.email, role: "owner" }

    assert_redirected_to edit_admin_tenant_path(@tenant)
    assert @tenant.owner?(@admin)
  end

  test "admin search matches tenant names and member emails" do
    users(:two).update_columns(email: "jana@firma-abc.sk")
    by_name = Tenant.create!(name: "ABC Holding", plan: :pro)
    other = Tenant.create!(name: "Iná firma", plan: :pro)
    sign_in @admin

    get admin_tenants_path(q: "abc")

    assert_response :success
    assert_includes response.body, by_name.name
    assert_includes response.body, @tenant.name
    assert_not_includes response.body, other.name
  end

  test "admin edit renders plan, features and members" do
    sign_in @admin

    get edit_admin_tenant_path(@tenant)

    assert_response :success
    assert_select "select[name='tenant[plan]']"
    assert_select "input[type=checkbox][name='tenant[features][]']", count: Tenant::AVAILABLE_FEATURES.size
  end

  test "admin sees the monthly usage of a tenant for billing" do
    @tenant.usage_records.create!(kind: :signature_request, source: :notification, created_at: Time.zone.local(2026, 9, 10))
    @tenant.usage_records.create!(kind: :timestamp, source: :archivation, quantity: 3, created_at: Time.zone.local(2026, 9, 20))
    @tenant.usage_records.create!(kind: :timestamp, source: :extension, created_at: Time.zone.local(2026, 8, 31))
    tenants(:one).usage_records.create!(kind: :timestamp, source: :extension, quantity: 7, created_at: Time.zone.local(2026, 9, 15))
    @tenant.usage_records.create!(kind: :signature_request, source: :recipient_signature, created_at: Time.zone.local(2026, 9, 30, 23))
    sign_in @admin

    get edit_admin_tenant_path(@tenant, month: "2026-09")

    assert_response :success
    assert_select "input[type=month][value='2026-09']"
    assert_select "tr", text: /#{I18n.t("admin.tenants.usage.sources.archivation")}\s*3/
    assert_select "tr", text: /#{I18n.t("admin.tenants.usage.total", kind: I18n.t("admin.tenants.usage.kinds.timestamp"))}\s*3/
    assert_select "tr", text: /#{I18n.t("admin.tenants.usage.sources.recipient_signature")}\s*1/
    assert_select "tr", text: /#{I18n.t("admin.tenants.usage.total", kind: I18n.t("admin.tenants.usage.kinds.signature_request"))}\s*2/
    assert_select "tr", text: /#{I18n.t("admin.tenants.usage.sources.extension")}/, count: 0
  end

  test "admin creates an organization for a new customer email" do
    sign_in @admin

    assert_difference -> { Tenant.count } => 2, -> { User.count } => 1 do
      assert_emails 1 do
        post admin_tenants_path, params: { owner_email: "Owner@Firma-ABC.sk", tenant: { name: "Firma ABC", plan: "pro", features: [ "", "api" ] } }
      end
    end

    tenant = Tenant.find_by!(name: "Firma ABC")
    owner = User.find_by!(email: "owner@firma-abc.sk")
    assert_redirected_to edit_admin_tenant_path(tenant)
    assert tenant.pro?
    assert_equal [ "api" ], tenant.features
    assert tenant.owner?(owner)
    assert owner.tenants.where.not(id: tenant.id).sole.basic?
    assert_not owner.confirmed?
  end

  test "creating an organization for an existing user keeps their personal tenant" do
    customer = User.create!(email: "customer-#{SecureRandom.hex(4)}@example.com")
    personal = customer.tenants.sole
    sign_in @admin

    post admin_tenants_path, params: { owner_email: customer.email, tenant: { name: "Firma ABC", plan: "pro" } }

    tenant = Tenant.find_by!(name: "Firma ABC")
    assert_equal [ personal, tenant ].sort_by(&:id), customer.reload.tenants.sort_by(&:id)
  end

  test "creating an organization requires an owner email" do
    sign_in @admin

    assert_no_difference -> { Tenant.count } do
      post admin_tenants_path, params: { owner_email: "", tenant: { name: "Firma ABC", plan: "pro" } }
    end

    assert_response :unprocessable_entity
  end

  test "admin new form asks for the owner email" do
    sign_in @admin

    get new_admin_tenant_path

    assert_response :success
    assert_select "input[name='owner_email']"
  end

  test "admin index lists tenants" do
    sign_in @admin

    get admin_tenants_path

    assert_response :success
    assert_includes response.body, @tenant.name
  end

  test "admin filters tenants by plan" do
    pro = Tenant.create!(name: "Firma PRO", plan: :pro)
    sign_in @admin

    get admin_tenants_path(plan: "pro")

    assert_response :success
    assert_equal [ pro.name ], listed_tenant_names
    assert_select "select[name=plan] option[selected][value=pro]"

    get admin_tenants_path(plan: "basic")

    assert_equal [ tenants(:one).name, @tenant.name ], listed_tenant_names
  end

  test "admin combines the search with the plan filter" do
    users(:two).update_columns(email: "jana@firma-abc.sk")
    pro = Tenant.create!(name: "ABC Holding", plan: :pro)
    Tenant.create!(name: "Iná firma", plan: :pro)
    sign_in @admin

    get admin_tenants_path(q: "abc", plan: "pro")

    assert_equal [ pro.name ], listed_tenant_names

    get admin_tenants_path(q: "abc", plan: "basic")

    assert_equal [ @tenant.name ], listed_tenant_names
  end

  test "admin index tells when no tenant matches the filter" do
    sign_in @admin

    get admin_tenants_path(plan: "pro")

    assert_response :success
    assert_select "td", text: I18n.t("admin.tenants.index.empty")
  end

  test "admin sorts tenants by id" do
    newest = Tenant.create!(name: "Aaa newest", plan: :pro)
    sign_in @admin

    get admin_tenants_path(sort: "id_asc")

    assert_equal [ tenants(:one), @tenant, newest ].sort_by(&:id).map(&:name), listed_tenant_names

    get admin_tenants_path(sort: "id_desc")

    assert_equal [ tenants(:one), @tenant, newest ].sort_by(&:id).reverse.map(&:name), listed_tenant_names
  end

  test "admin index shows and sorts by the usage in the selected month" do
    big = Tenant.create!(name: "Veľká firma", plan: :pro)
    big.usage_records.create!(kind: :signature_request, source: :notification, created_at: Time.zone.local(2026, 9, 30, 18))
    big.usage_records.create!(kind: :signature_request, source: :notification, created_at: Time.zone.local(2026, 9, 2))
    big.usage_records.create!(kind: :timestamp, source: :extension, created_at: Time.zone.local(2026, 9, 2))
    @tenant.usage_records.create!(kind: :signature_request, source: :notification, created_at: Time.zone.local(2026, 9, 1))
    @tenant.usage_records.create!(kind: :timestamp, source: :archivation, quantity: 5, created_at: Time.zone.local(2026, 9, 10))
    @tenant.usage_records.create!(kind: :signature_request, source: :notification, created_at: Time.zone.local(2026, 10, 1))
    sign_in @admin

    get admin_tenants_path(month: "2026-09", sort: "signature_requests")

    assert_response :success
    assert_select "input[type=month][value='2026-09']"
    assert_equal [ big.name, @tenant.name, tenants(:one).name ], listed_tenant_names
    assert_equal({ big.name => [ 2, 1 ], @tenant.name => [ 1, 5 ], tenants(:one).name => [ 0, 0 ] }, listed_usage)

    get admin_tenants_path(month: "2026-09", sort: "timestamps")

    assert_equal [ @tenant.name, big.name, tenants(:one).name ], listed_tenant_names

    get admin_tenants_path(month: "2026-10", sort: "signature_requests")

    assert_equal [ @tenant.name, tenants(:one).name, big.name ], listed_tenant_names
  end

  test "non-admins cannot manage tenants" do
    @admin.update_column(:features, [])
    sign_in @admin

    get admin_tenants_path

    assert_response :not_found
  end

  private

  def listed_tenant_names
    css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
  end

  # Tenant name => [ documents sent for signature, timestamps ] in the listed month.
  def listed_usage
    css_select("tbody tr").to_h { |row| [ row.css("td")[1].text.strip, row.css("td")[5..6].map { |cell| cell.text.to_i } ] }
  end
end
