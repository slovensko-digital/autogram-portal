require "test_helper"

# == Schema Information
#
# Table name: tenants
#
#  id                   :bigint           not null, primary key
#  api_token_public_key :string
#  features             :string           default([]), not null, is an Array
#  name                 :string           not null
#  plan                 :string           default("basic"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_tenants_on_plan  (plan)
#
class TenantTest < ActiveSupport::TestCase
  test "creating a user creates a personal basic tenant owned by the user" do
    user = User.create!(email: "new-user-#{SecureRandom.hex(4)}@example.com", name: "Jana Nová")

    tenant = user.tenants.sole
    assert tenant.basic?
    assert_equal "Jana Nová", tenant.name
    assert tenant.owner?(user)
    assert_equal tenant, user.last_tenant
  end

  test "invited user does not get a personal tenant" do
    user = User.create!(email: "invited-#{SecureRandom.hex(4)}@example.com", skip_personal_tenant: true)

    assert_empty user.tenants
  end

  test "basic tenant accepts only a single member" do
    tenant = tenants(:one)
    membership = tenant.memberships.new(user: users(:two))

    assert_not membership.save
    assert_includes membership.errors[:base], I18n.t("activerecord.errors.models.membership.attributes.base.plan_member_limit", count: 1)
  end

  test "pro tenant accepts additional members" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)

    assert tenant.memberships.create!(user: users(:two))
    assert_equal 2, tenant.users.count
  end

  test "pro tenant with several members cannot be downgraded to basic" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    tenant.memberships.create!(user: users(:two))

    assert_not tenant.update(plan: :basic)
    assert tenant.errors.of_kind?(:plan, :too_many_members)
  end

  test "features are limited to tenant features" do
    tenant = tenants(:one)
    tenant.update!(features: [ "api", "admin", "", "archivation", "api" ])

    assert_equal [ "api", "archivation" ], tenant.features
    assert tenant.api_enabled?
    assert tenant.archivation_enabled?
  end

  test "api token public key must be a valid PEM key" do
    tenant = tenants(:one)

    assert_not tenant.update(api_token_public_key: "not a key")
    assert tenant.update(api_token_public_key: OpenSSL::PKey::RSA.generate(2048).public_to_pem)
  end

  test "adding a member removes their unused personal basic tenant" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    user = User.create!(email: "joining-#{SecureRandom.hex(4)}@example.com")
    personal = user.tenants.sole

    tenant.add_member!(user)

    assert_not Tenant.exists?(personal.id)
    assert_equal [ tenant ], user.reload.tenants.to_a
  end

  test "adding a member keeps a personal tenant that holds documents" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    user = User.create!(email: "joining-#{SecureRandom.hex(4)}@example.com")
    personal = user.tenants.sole
    create_bundle(tenant: personal)

    tenant.add_member!(user)

    assert Tenant.exists?(personal.id)
    assert_equal 2, user.reload.tenants.count
  end

  test "adding a member keeps other shared or pro tenants" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    other = tenants(:two)
    other.update!(plan: :pro)

    tenant.add_member!(users(:two))

    assert Tenant.exists?(other.id)
  end

  test "last owner membership cannot be destroyed" do
    membership = memberships(:one_owner)

    assert_not membership.destroy
    assert Membership.exists?(membership.id)
  end

  test "last owner cannot be demoted" do
    membership = memberships(:one_owner)

    assert_not membership.update(role: :member)
    assert membership.errors.of_kind?(:role, :last_owner)
  end

  test "destroying a user removes tenants where they are the only member" do
    user = User.create!(email: "leaving-#{SecureRandom.hex(4)}@example.com")
    tenant = user.tenants.sole
    bundle = create_bundle(tenant: tenant)

    user.destroy!

    assert_not Tenant.exists?(tenant.id)
    assert_not Bundle.exists?(bundle.id)
  end

  test "destroying a user keeps shared tenants and their data" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    colleague = User.create!(email: "colleague-#{SecureRandom.hex(4)}@example.com")
    tenant.memberships.create!(user: colleague)
    bundle = create_bundle(tenant: tenant)

    colleague.destroy!

    assert Tenant.exists?(tenant.id)
    assert_equal tenant, bundle.reload.tenant
  end

  test "last owner of a shared tenant cannot delete the account" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    tenant.memberships.create!(user: users(:two))

    assert_not users(:one).destroy
    assert users(:one).errors.of_kind?(:base, :last_tenant_owner)
    assert User.exists?(users(:one).id)
  end

  private

  def create_bundle(tenant:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 tenant test"),
      filename: "tenant.pdf",
      content_type: "application/pdf"
    )
    contract = Contract.new(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )

    Bundle.create!(tenant: tenant, contracts: [ contract ])
  end
end
