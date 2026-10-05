# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  completed_onboardings  :jsonb            not null
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  email                  :string
#  encrypted_password     :string           default(""), not null
#  failed_attempts        :integer          default(0), not null
#  features               :text             default([]), is an Array
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  locale                 :string           default("sk")
#  locked_at              :datetime
#  name                   :string
#  qscd                   :integer
#  remember_created_at    :datetime
#  remember_token         :string
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  unconfirmed_email      :string
#  unlock_token           :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  last_tenant_id         :bigint
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token) UNIQUE
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_last_tenant_id        (last_tenant_id)
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (last_tenant_id => tenants.id) ON DELETE => nullify
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

  test "every qscd except none belongs to exactly one onboarding group" do
    grouped = User::QSCD_GROUPS.values.flatten

    assert_equal grouped.uniq, grouped
    assert_equal User.qscds.keys - [ "none" ], grouped.sort_by { |qscd| User.qscds[qscd] }
  end

  test "qscd group and legacy cards" do
    assert_equal :sk_eid, User.qscd_group("eid_2024")
    assert_equal :cz_eid, User.qscd_group("cz_eid_2018")
    assert_equal :tokens, User.qscd_group(:ica_securestore)
    assert_nil User.qscd_group(nil)
    assert_nil User.qscd_group("unknown")

    assert User.legacy_eid_card?("cz_eid_2012")
    assert User.legacy_eid_card?(:eid_2013)
    assert_not User.legacy_eid_card?("cz_eid_2018")
    assert_not User.legacy_eid_card?("pkcs11_other")
  end
end
