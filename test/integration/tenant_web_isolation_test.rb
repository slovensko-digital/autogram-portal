require "test_helper"

class TenantWebIsolationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @other_user = users(:two)
    @user.update_columns(email: "owner@example.com", confirmed_at: Time.current)
    @other_user.update_columns(email: "member@example.com", confirmed_at: Time.current)
    bundles(:one).update_columns(uuid: SecureRandom.uuid)
    bundles(:two).update_columns(uuid: SecureRandom.uuid)
    contracts(:one).update_columns(uuid: SecureRandom.uuid)
    contracts(:two).update_columns(uuid: SecureRandom.uuid)
    accept_current_policies!(@other_user)
  end

  test "owner-facing endpoints reject resources from another tenant" do
    sign_in @user

    get bundle_path(bundles(:two))
    assert_response :not_found

    delete contract_path(contracts(:two))
    assert_response :not_found
    assert Contract.exists?(contracts(:two).id)

    get bundle_recipients_path(bundles(:two))
    assert_response :not_found
  end

  test "members of an organization share owner access regardless of original author" do
    organization = Tenant.create!(name: "Shared organization", kind: :organization)
    organization.tenant_users.create!(user: @user, role: :owner)
    organization.tenant_users.create!(user: @other_user, role: :member)
    bundle = bundles(:one)
    bundle.contracts.update_all(tenant_id: organization.id)
    bundle.update_columns(tenant_id: organization.id)
    @other_user.update!(current_tenant: organization)

    sign_in @other_user

    get bundle_path(bundle)
    assert_response :success

    patch bundle_path(bundle), params: { bundle: { note: "Updated by another member" } }
    assert_redirected_to bundle_path(bundle)
    assert_equal "Updated by another member", bundle.reload.note

    get bundle_recipients_path(bundle)
    assert_response :success
  end

  private

  def accept_current_policies!(user)
    PolicyVersions.current.each do |policy_type, version|
      user.policy_consents.find_or_create_by!(policy_type: policy_type, policy_version: version) do |consent|
        consent.source = "re_consent"
        consent.accepted_at = Time.current
      end
    end
  end
end
