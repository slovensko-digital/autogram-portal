# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  admin                  :boolean          default(FALSE), not null
#  completed_onboardings  :jsonb            not null
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  email                  :string
#  encrypted_password     :string           default(""), not null
#  failed_attempts        :integer          default(0), not null
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  locale                 :string           default("sk")
#  locked_at              :datetime
#  name                   :string
#  qscd                   :integer
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  unconfirmed_email      :string
#  unlock_token           :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  current_tenant_id      :bigint
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token) UNIQUE
#  index_users_on_current_tenant_id     (current_tenant_id)
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (current_tenant_id => tenants.id) ON DELETE => nullify
#
require "test_helper"
require "ostruct"

class UserTest < ActiveSupport::TestCase
  def auth_double(email:, name: "Test User", provider: "google_oauth2", uid: "uid123")
    OpenStruct.new(
      provider: provider,
      uid:      uid,
      info:     OpenStruct.new(email: email, name: name)
    )
  end

  test "returns existing user when identity is found" do
    user = users(:one)
    identity = user.identities.create!(provider: "google_oauth2", uid: "known_uid")
    auth = auth_double(email: user.email, uid: identity.uid)

    result = User.find_or_link_from_provider_data(auth)
    assert_equal user, result
  end

  test "links identity and returns existing user matched by email" do
    user = users(:one)
    auth = auth_double(email: user.email, uid: "new_uid_for_one")

    assert_no_difference "User.count" do
      result = User.find_or_link_from_provider_data(auth)
      assert_equal user, result
    end
  end

  test "returns nil for a brand-new email address" do
    auth = auth_double(email: "brand_new_#{SecureRandom.hex(4)}@example.com")

    result = User.find_or_link_from_provider_data(auth)
    assert_nil result
  end

  test "user with all current consents returns true" do
    assert users(:one).accepted_current_policies?
  end

  test "user without any consents returns false" do
    assert_not users(:two).accepted_current_policies?
  end

  test "creation atomically creates and selects an owned personal tenant" do
    user = build_user

    assert_difference [ "User.count", "Tenant.count", "TenantUser.count" ], 1 do
      user.save!
    end

    assert_equal user.current_tenant, user.owned_tenants.freemium.first
    assert_equal user, user.current_tenant.tenant_users.owner.sole.user
  end

  test "personal tenant failure rolls back user creation" do
    user = build_user
    user.define_singleton_method(:create_personal_tenant!) do
      tenant = Tenant.create!(name: "Rolled back", kind: :freemium)
      raise ActiveRecord::RecordInvalid, tenant
    end

    assert_no_difference [ "User.count", "Tenant.count", "TenantUser.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) do
        user.save!
      end
    end
  end

  test "features delegate to current tenant while admin remains global" do
    user = users(:one)
    user.current_tenant.update!(features: %w[archivation federation])
    organization = Tenant.create!(name: "Limited organization", kind: :organization, features: [])
    organization.tenant_users.create!(user: user, role: :member)

    assert user.admin?
    assert_not users(:two).admin?
    assert user.archivation_enabled?
    assert user.federation_enabled?

    user.update_column(:current_tenant_id, organization.id)
    user.current_tenant = organization

    assert user.admin?
    assert_not user.archivation_enabled?
    assert_not user.federation_enabled?
  end

  test "current tenant must be one of the user's tenants" do
    user = users(:two)
    user.current_tenant = tenants(:one)

    assert_not user.valid?
    assert_predicate user.errors[:current_tenant], :any?
  end

  test "deleting a user destroys their personal tenant without destroying organization data" do
    user = build_user
    user.save!
    personal_tenant = user.current_tenant
    organization = Tenant.create!(name: "Organization", kind: :organization)
    organization.tenant_users.create!(user: user, role: :owner)
    organization.tenant_users.create!(user: users(:two), role: :member)
    organization_key = ApiKey.create!(tenant: organization, user: user, name: "Organization key", public_key: "key")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 organization data"),
      filename: "organization.pdf",
      content_type: "application/pdf"
    )
    contract = Contract.create!(
      tenant: organization,
      user: user,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    bundle = Bundle.create!(tenant: organization, author: user, contracts: [ contract ])
    validation_record = ContractValidationRecord.create!(
      tenant: organization,
      user: user,
      contract: contract,
      source_contract_uuid: contract.uuid,
      source_version_number: 1,
      filename: "organization.pdf",
      document_hash: Digest::SHA256.hexdigest("organization"),
      validation_details: {}
    )

    user.destroy!

    assert_not Tenant.exists?(personal_tenant.id)
    assert Tenant.exists?(organization.id)
    assert_nil organization_key.reload.user
    assert_nil bundle.reload.author
    assert_nil contract.reload.user
    assert_nil validation_record.reload.user
    assert_equal [ users(:two) ], organization.reload.users
  end

  private

  def build_user
    User.new(
      name: "New User",
      email: "new-#{SecureRandom.hex(4)}@example.com",
      agree_to_policies: "1"
    ).tap(&:skip_confirmation!)
  end
end
