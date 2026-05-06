# == Schema Information
#
# Table name: user_policy_consents
#
#  id             :bigint           not null, primary key
#  accepted_at    :datetime         not null
#  ip_address     :string
#  policy_type    :string           not null
#  policy_version :string           not null
#  source         :string           not null
#  user_agent     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_policy_consents_on_user_id                  (user_id)
#  index_user_policy_consents_on_user_id_and_accepted_at  (user_id,accepted_at)
#  index_user_policy_consents_on_user_policy_version      (user_id,policy_type,policy_version)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class UserPolicyConsentTest < ActiveSupport::TestCase
  FakeRequest = Struct.new(:remote_ip, :user_agent)
  def setup
    @user = users(:one)
  end

  test "valid consent record" do
    consent = UserPolicyConsent.new(
      user:           @user,
      policy_type:    "terms",
      policy_version: "1",
      source:         "email_signup",
      accepted_at:    Time.current
    )
    assert consent.valid?
  end

  test "invalid policy_type is rejected" do
    consent = UserPolicyConsent.new(
      user:           @user,
      policy_type:    "unknown",
      policy_version: "1",
      source:         "email_signup",
      accepted_at:    Time.current
    )
    assert_not consent.valid?
    assert_includes consent.errors[:policy_type], I18n.t("errors.messages.inclusion")
  end

  test "invalid source is rejected" do
    consent = UserPolicyConsent.new(
      user:           @user,
      policy_type:    "terms",
      policy_version: "1",
      source:         "invalid_source",
      accepted_at:    Time.current
    )
    assert_not consent.valid?
  end

  test "record_current_for creates records for all current policy types" do
    user    = users(:two)
    request = FakeRequest.new("127.0.0.1", "TestAgent")

    assert_difference "UserPolicyConsent.count", PolicyVersions.current.size do
      UserPolicyConsent.record_current_for(user: user, source: "email_signup", request: request)
    end
  end

  test "record_current_for is idempotent" do
    user    = users(:two)
    request = FakeRequest.new("127.0.0.1", "TestAgent")

    UserPolicyConsent.record_current_for(user: user, source: "email_signup", request: request)

    assert_no_difference "UserPolicyConsent.count" do
      UserPolicyConsent.record_current_for(user: user, source: "email_signup", request: request)
    end
  end
end
