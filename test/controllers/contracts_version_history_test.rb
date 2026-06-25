require "test_helper"

class ContractsVersionHistoryTest < ActionController::TestCase
  tests ContractsController

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

  test "content_versions shows signed content history for contract author" do
    contract = create_contract_with_versions

    get :content_versions, params: { id: contract.uuid }

    assert_response :success
    assert_includes response.body, "Version 2"
    assert_includes response.body, "Version 1"
    assert_includes response.body, "Current"
    assert_includes response.body, rails_blob_path(contract.content_versions.first.file, disposition: "attachment")
  end

  test "content_versions is forbidden without archivation feature" do
    @user.update_column(:features, [])
    contract = create_contract_with_versions

    get :content_versions, params: { id: contract.uuid }

    assert_response :forbidden
  end

  private

  def create_contract_with_versions
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "contract-version-history.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      user: @user,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    ).tap do |contract|
      contract.add_signed_content_version!(
        content: "signed-v1",
        filename: "contract-version-history-signed-v1.pdf",
        content_type: "application/pdf",
        origin: "uploaded_signed"
      )
      contract.add_signed_content_version!(
        content: "signed-v2",
        filename: "contract-version-history-signed-v2.pdf",
        content_type: "application/pdf",
        origin: "extension"
      )
      contract.reload
    end
  end
end
