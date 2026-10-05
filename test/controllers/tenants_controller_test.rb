require "test_helper"

class TenantsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper

  setup do
    @owner = users(:one)
    @owner.update_columns(email: "owner@example.com", confirmed_at: Time.current)
    @colleague = users(:two)
    @colleague.update_columns(email: "colleague@example.com", confirmed_at: Time.current)
    accept_policies!(@colleague)
    @tenant = tenants(:one)
  end

  test "settings page shows the account and the organization with its members" do
    @tenant.update!(plan: :pro, features: [ "api" ])
    @tenant.memberships.create!(user: @colleague)
    sign_in @owner

    get edit_user_registration_path

    assert_response :success
    assert_select "section#account"
    assert_select "section#organization"
    assert_includes response.body, @colleague.email
    assert_select "form[action='#{tenant_memberships_path}']"
    assert_select "textarea[name='tenant[api_token_public_key]']:not([disabled])"
  end

  test "the chosen tenant cannot be changed until sign out" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)
    sign_in @owner
    post tenant_selection_path(tenant_id: @tenant.id)

    get dashboard_path
    assert_response :success
    assert_includes response.body, @tenant.name
    assert_select "form[action^='#{tenant_selection_path}']", count: 0

    get tenant_selection_path
    assert_redirected_to dashboard_path

    post tenant_selection_path(tenant_id: tenants(:two).id)
    assert_redirected_to dashboard_path
    assert_equal @tenant.id, session[:current_tenant_id]

    sign_out @owner
    sign_in @owner
    get dashboard_path
    assert_redirected_to tenant_selection_path
  end

  test "selection page offers no navigation until a tenant is chosen" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)
    sign_in @owner

    get tenant_selection_path

    assert_response :success
    assert_select "a[href='#{dashboard_path}']", count: 0
    assert_select "a[href='#{edit_user_registration_path}']", count: 0
    assert_select "a[href='#{new_user_session_path}']", count: 0
    assert_select "form[action='#{destroy_user_session_path}'] input[name='_method'][value='delete']"
  end

  test "user works only with account pages until a tenant is chosen" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)
    sign_in @owner

    get dashboard_path
    assert_redirected_to tenant_selection_path

    get edit_user_registration_path
    assert_response :success
    assert_select "section#account"
    assert_select "section#organization", count: 0

    post tenant_selection_path(tenant_id: @tenant.id)
    assert_redirected_to dashboard_path

    get edit_user_registration_path
    assert_select "section#organization"
  end

  test "embedded signing works before a tenant is chosen" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)
    bundle = create_bundle(tenant: Tenant.create!(name: "Sender"), name: "Public bundle")
    bundle.update!(publicly_visible: true)
    sign_in @owner

    get sign_bundle_path(bundle, iframe: 1)

    assert_response :success
    assert_nil session[:current_tenant_id]
  end

  test "iframe signing does not skip tenant selection on other pages" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)
    sign_in @owner

    get dashboard_path(iframe: 1)

    assert_redirected_to tenant_selection_path
  end

  test "tenant selection without signing in sends to sign in" do
    get tenant_selection_path

    assert_redirected_to new_user_session_path
  end

  test "user with several tenants chooses one after signing in and returns to the requested page" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)
    sign_in @owner

    get bundles_path
    assert_redirected_to tenant_selection_path

    follow_redirect!
    assert_response :success
    assert_select "form[action='#{tenant_selection_path(tenant_id: @tenant.id)}']", text: /#{I18n.t("tenant_selections.show.personal")}/
    assert_select "form[action='#{tenant_selection_path(tenant_id: tenants(:two).id)}']", text: /#{tenants(:two).name}/

    post tenant_selection_path(tenant_id: tenants(:two).id)
    assert_redirected_to bundles_path
    assert_equal tenants(:two).id, session[:current_tenant_id]
  end

  test "user with a single tenant is not asked to choose" do
    sign_in @owner

    get dashboard_path

    assert_response :success
    assert_equal @tenant.id, session[:current_tenant_id]
  end

  test "magic-link authentication succeeds with inherited verification enabled" do
    get user_magic_link_path, params: {
      user: { email: @owner.email, token: @owner.encode_passwordless_token }
    }

    assert_response :redirect
    assert_equal @owner, request.env["warden"].user(:user)

    get dashboard_path

    assert_response :success
    assert_equal @tenant.id, session[:current_tenant_id]
  end

  test "magic-link authentication requires tenant selection for multiple tenants" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @owner)

    get user_magic_link_path, params: {
      user: { email: @owner.email, token: @owner.encode_passwordless_token }
    }

    assert_response :redirect
    assert_equal @owner, request.env["warden"].user(:user)

    get dashboard_path

    assert_redirected_to tenant_selection_path
    assert_equal @owner, request.env["warden"].user(:user)

    post tenant_selection_path(tenant_id: @tenant.id)

    assert_redirected_to dashboard_path
    assert_equal @tenant.id, session[:current_tenant_id]
    assert_equal @owner, request.env["warden"].user(:user)
  end

  test "lists only bundles of the current tenant" do
    own_bundle = create_bundle(tenant: @tenant, name: "Own bundle")
    create_bundle(tenant: tenants(:two), name: "Foreign bundle")

    sign_in @owner
    get bundles_path

    assert_response :success
    assert_includes response.body, own_bundle.name
    assert_not_includes response.body, "Foreign bundle"
  end

  test "pro tenant members share bundles" do
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: @colleague)
    bundle = create_bundle(tenant: @tenant, name: "Shared bundle")

    sign_in @colleague
    post tenant_selection_path(tenant_id: @tenant.id)
    assert_redirected_to dashboard_path

    get bundles_path
    assert_includes response.body, "Shared bundle"

    get bundle_path(bundle)
    assert_response :success
  end

  test "opening a bundle of another own tenant points to that tenant" do
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: @colleague)
    bundle = create_bundle(tenant: @tenant, name: "Linked bundle")

    sign_in @colleague
    post tenant_selection_path(tenant_id: tenants(:two).id)
    get bundle_path(bundle)

    assert_redirected_to dashboard_path
    assert_equal I18n.t("tenants.alerts.other_tenant_record", name: @tenant.name), flash[:alert]
    assert_equal tenants(:two).id, session[:current_tenant_id]
  end

  test "non-members cannot open a tenant bundle" do
    bundle = create_bundle(tenant: @tenant, name: "Private bundle")

    sign_in @colleague
    get bundle_path(bundle)

    assert_response :not_found
  end

  test "cannot choose a tenant without membership" do
    second = Tenant.create!(name: "Second", plan: :pro)
    second.memberships.create!(user: @colleague, role: :owner)
    sign_in @colleague

    post tenant_selection_path(tenant_id: @tenant.id)

    assert_response :not_found
    assert_nil session[:current_tenant_id]
  end


  test "owner of a pro tenant invites a new user who also gets a personal tenant" do
    @tenant.update!(plan: :pro)
    sign_in @owner

    assert_difference -> { User.count } => 1, -> { Tenant.count } => 1 do
      assert_emails 1 do
        post tenant_memberships_path, params: { membership: { email: "New.Member@Example.com", role: "member" } }
      end
    end

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    invited = User.find_by!(email: "new.member@example.com")
    assert_includes invited.tenants, @tenant
    assert invited.tenants.where.not(id: @tenant.id).sole.basic?
    assert_not invited.confirmed?
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "new.member@example.com" ], mail.to
    assert_includes mail.body.encoded, invited.confirmation_token
  end

  test "owner of a pro tenant adds an existing user" do
    @tenant.update!(plan: :pro)
    sign_in @owner

    assert_no_difference -> { User.count } do
      post tenant_memberships_path, params: { membership: { email: @colleague.email } }
    end

    assert @colleague.member_of?(@tenant)
  end

  test "basic tenant cannot invite members" do
    sign_in @owner

    assert_no_difference -> { Membership.count } do
      post tenant_memberships_path, params: { membership: { email: @colleague.email } }
    end

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_not @colleague.member_of?(@tenant)
  end

  test "members cannot manage the tenant" do
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: @colleague)
    sign_in @colleague
    post tenant_selection_path(tenant_id: @tenant.id)

    patch tenant_path, params: { tenant: { name: "Hijacked" } }
    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal "Tenant One", @tenant.reload.name

    post tenant_memberships_path, params: { membership: { email: "someone@example.com" } }
    assert_nil User.find_by(email: "someone@example.com")
  end

  test "member settings remain read only even with api access" do
    @tenant.update!(plan: :pro, features: [ "api" ])
    @tenant.memberships.create!(user: @colleague)
    sign_in @colleague
    post tenant_selection_path(tenant_id: @tenant.id)

    get edit_user_registration_path

    assert_response :success
    assert_select "textarea[name='tenant[api_token_public_key]'][disabled]"
    assert_select "form[action='#{tenant_memberships_path}']", count: 0
    assert_select "form[action='#{tenant_membership_path(@tenant.memberships.find_by!(user: @owner))}']", count: 0

    assert_no_difference -> { Membership.count } do
      patch tenant_path, params: { tenant: { api_token_public_key: "ignored" } }
    end
    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal I18n.t("tenants.alerts.owner_required"), flash[:alert]
    assert_nil @tenant.reload.api_token_public_key
  end

  test "owner cannot rename the tenant" do
    @tenant.update!(features: [ "api" ])
    sign_in @owner

    get edit_user_registration_path
    assert_select "input[name='tenant[name]'][disabled]"

    patch tenant_path, params: { tenant: { name: "Renamed" } }
    assert_equal "Tenant One", @tenant.reload.name
  end

  test "api key can be set only when api access is enabled" do
    key = OpenSSL::PKey::RSA.generate(2048).public_to_pem
    sign_in @owner

    patch tenant_path, params: { tenant: { api_token_public_key: key } }
    assert_nil @tenant.reload.api_token_public_key

    @tenant.update!(features: [ "api" ])
    patch tenant_path, params: { tenant: { api_token_public_key: key } }
    assert_equal key, @tenant.reload.api_token_public_key
  end

  test "member can leave a tenant" do
    @tenant.update!(plan: :pro)
    membership = @tenant.memberships.create!(user: @colleague)
    sign_in @colleague
    post tenant_selection_path(tenant_id: @tenant.id)

    post leave_tenant_path

    assert_redirected_to dashboard_path
    assert_not Membership.exists?(membership.id)
    follow_redirect!
    assert_response :success
    assert_equal I18n.t("tenants.leave.success", name: @tenant.name), flash[:notice]
    assert_equal tenants(:two).id, session[:current_tenant_id]
  end

  test "owner update without api access succeeds without permitting attributes" do
    sign_in @owner

    patch tenant_path, params: { tenant: { name: "Renamed", plan: "pro", features: [ "api" ], api_token_public_key: "ignored" } }

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal I18n.t("tenants.update.success"), flash[:notice]
    assert_equal "Tenant One", @tenant.reload.name
    assert @tenant.basic?
    assert_empty @tenant.features
    assert_nil @tenant.api_token_public_key

    patch tenant_path
    assert_response :bad_request
  end

  test "member cannot remove another membership" do
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: @colleague)
    sign_in @colleague
    post tenant_selection_path(tenant_id: @tenant.id)

    assert_no_difference -> { Membership.count } do
      delete tenant_membership_path(@tenant.memberships.find_by!(user: @owner))
    end

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal I18n.t("tenants.alerts.owner_required"), flash[:alert]
  end

  test "owner cannot remove a membership from another tenant" do
    sign_in @owner

    assert_no_difference -> { Membership.count } do
      delete tenant_membership_path(tenants(:two).memberships.find_by!(user: @colleague))
    end

    assert_response :not_found
  end

  test "last owner removal returns the model error" do
    sign_in @owner
    membership = @tenant.memberships.find_by!(user: @owner)

    assert_no_difference -> { Membership.count } do
      delete tenant_membership_path(membership)
    end

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal I18n.t("activerecord.errors.models.membership.attributes.base.last_owner"), flash[:alert]
  end

  test "owner can remove their own membership when another owner remains" do
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: @colleague, role: :owner)
    membership = @tenant.memberships.find_by!(user: @owner)
    sign_in @owner

    get edit_user_registration_path
    assert_select "form[action='#{tenant_membership_path(membership)}']", count: 0

    assert_difference -> { Membership.count }, -1 do
      delete tenant_membership_path(membership)
    end

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal I18n.t("tenants.memberships.destroy.success", email: @owner.email), flash[:notice]
    assert_not @owner.member_of?(@tenant)
  end

  test "last owner cannot leave but remains signed in" do
    sign_in @owner

    assert_no_difference -> { Membership.count } do
      post leave_tenant_path
    end

    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal I18n.t("activerecord.errors.models.membership.attributes.base.last_owner"), flash[:alert]
    get dashboard_path
    assert_response :success
  end

  test "inviting an existing user keeps their personal tenant" do
    @tenant.update!(plan: :pro)
    newcomer = User.create!(email: "newcomer@example.com")
    personal = newcomer.tenants.sole
    sign_in @owner

    post tenant_memberships_path, params: { membership: { email: " NewComer@example.com " } }

    assert_equal [ personal, @tenant ].sort_by(&:id), newcomer.reload.tenants.sort_by(&:id)
  end

  private

  def accept_policies!(user)
    PolicyVersions.current.each do |policy_type, version|
      user.policy_consents.create!(policy_type: policy_type, policy_version: version, source: "email_signup", accepted_at: Time.current)
    end
  end

  def create_bundle(tenant:, name:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 tenant test"),
      filename: "tenant.pdf",
      content_type: "application/pdf"
    )
    contract = Contract.new(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )

    Bundle.create!(tenant: tenant, name: name, contracts: [ contract ])
  end
end
