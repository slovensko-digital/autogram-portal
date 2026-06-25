require "test_helper"

class DashboardControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests DashboardController

  setup do
    @user = users(:one)
    @user.update_column(:features, [ "archivation" ])
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "index renders validation warning for records expiring within two months" do
    create_record(user: @user, expires_at: 3.weeks.from_now)
    create_record(user: @user, expires_at: 8.months.from_now)

    get :index

    assert_response :success
    assert_includes response.body, I18n.t("dashboard.index.validation_warning.title")
    assert_includes response.body, contract_validation_records_path(state: "expiring")
  end

  test "index hides archivation widgets when feature is disabled" do
    @user.update_column(:features, [])
    create_record(user: @user, expires_at: 3.weeks.from_now)

    get :index

    assert_response :success
    assert_not_includes response.body, I18n.t("dashboard.index.validation_warning.title")
    assert_not_includes response.body, I18n.t("dashboard.index.quick_actions.validation_archive")
  end

  private

  def create_record(user:, expires_at: nil)
    ContractValidationRecord.create!(
      user: user,
      source_contract_uuid: SecureRandom.uuid,
      source_version_number: 1,
      filename: "signed-contract.pdf",
      document_hash: Digest::SHA256.hexdigest(SecureRandom.hex(8)),
      signature_levels: [ "BASELINE_T" ],
      signatures_count: 1,
      expires_at: expires_at,
      validation_details: {}
    )
  end
end
