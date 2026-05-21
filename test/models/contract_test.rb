# == Schema Information
#
# Table name: contracts
#
#  id                           :bigint           not null, primary key
#  allowed_methods              :string           default(["qes"]), is an Array
#  author_notifications_enabled :boolean          default(FALSE), not null
#  temporary_storage_reason     :string
#  uuid                         :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  bundle_id                    :bigint
#  user_id                      :bigint
#
# Indexes
#
#  index_contracts_on_bundle_id                 (bundle_id)
#  index_contracts_on_temporary_storage_reason  (temporary_storage_reason)
#  index_contracts_on_user_id                   (user_id)
#  index_contracts_on_uuid                      (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class ContractTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "does not notify standalone contract author by default" do
    contract = Contract.new(user: @user)
    contract.define_singleton_method(:awaiting_signature?) { false }

    assert_not contract.should_notify_user?
  end

  test "notifies standalone contract author when enabled" do
    contract = Contract.new(user: @user, author_notifications_enabled: true)
    contract.define_singleton_method(:awaiting_signature?) { false }

    assert contract.should_notify_user?
  end

  test "does not notify author when signer is the author" do
    contract = Contract.new(user: @user, author_notifications_enabled: true)
    signer = Struct.new(:user).new(@user)
    contract.define_singleton_method(:awaiting_signature?) { false }

    assert_not contract.should_notify_user?(signer: signer)
  end
end
