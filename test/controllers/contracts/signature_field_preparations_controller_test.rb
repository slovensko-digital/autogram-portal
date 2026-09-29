require "test_helper"

class Contracts::SignatureFieldPreparationsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests Contracts::SignatureFieldPreparationsController

  setup do
    @user = users(:one)
    @user.update_column(:email, "owner@example.com")
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "index renders signature field preparation form for eligible author" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :success
    assert_select "form[action='#{contract_signature_field_preparations_path(contract)}']"
    assert_select "option[value='#{recipient.uuid}']", text: recipient.display_name
    assert_select "[data-controller='visual-stamp']"
    assert_select "[data-signature-field-preparations-layout='page']"
    assert_select "canvas[data-visual-stamp-target='pdfCanvas']"
    assert_select "[data-visual-stamp-target='pageCount']"
    assert_select "[data-visual-stamp-target='boxLabel']"
    assert_select "a[href='#{bundle_path(contract.bundle)}']"
    assert_select "form[action=?]", finalize_contract_signature_field_preparations_path(contract), count: 0
    assert_includes response.body, I18n.t("contracts.signature_field_preparations.index.status.none")
  end

  test "index preview uses latest source document when a visual version already exists" do
    contract, = create_bundle_contract_with_recipient(author: @user)
    contract.add_signed_content_version!(
      content: "%PDF-1.4 visually stamped content",
      filename: "signature-field-test-visual.pdf",
      content_type: "application/pdf",
      origin: "visual"
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :success
    assert_includes response.body, rails_blob_path(contract.reload.latest_source_content_version.file, disposition: "inline")
    assert_not_includes response.body, rails_blob_path(contract.documents.first.blob, disposition: "inline")
  end

  test "index hides recipients that already have linked signature fields and exposes existing preview data" do
    contract, first_recipient = create_bundle_contract_with_recipient(author: @user)
    second_recipient = contract.bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    contract.signature_field_preparations.create!(
      recipient: first_recipient,
      document: contract.documents.first,
      page: 1,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :success
    assert_select "option[value='#{first_recipient.uuid}']", count: 0
    assert_select "option[value='#{second_recipient.uuid}']", text: second_recipient.display_name
    assert_select "form[data-visual-stamp-existing-fields-value*='#{first_recipient.display_name}']"
    assert_select "[data-visual-stamp-target='existingFieldsLayer']"
    assert_select "form[action=?]", finalize_contract_signature_field_preparations_path(contract)
    assert_includes response.body, I18n.t("contracts.signature_field_preparations.index.recipients.placed", page: 1)
    assert_select "form[action=?]", contract_signature_field_preparation_path(contract, contract.signature_field_preparations.first)
  end

  test "index shows all assigned state when every recipient has a field" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 1,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :success
    assert_select "select[name='signature_field_preparation[recipient_uuid]']", count: 0
    assert_includes response.body, I18n.t("contracts.signature_field_preparations.index.form.all_assigned_title")
  end

  test "index shows ready state once the prepared signing pdf exists" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 1,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )
    contract.add_prepared_signature_fields_content_version!(
      content: "prepared pdf content",
      filename: "prepared.pdf",
      content_type: "application/pdf"
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :success
    assert_includes response.body, I18n.t("contracts.signature_field_preparations.index.status.ready_title")
    assert_select "form[action=?]", finalize_contract_signature_field_preparations_path(contract), count: 0
  end

  test "create stores a prepared signature field" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      post :create, params: {
        contract_id: contract.uuid,
        signature_field_preparation: {
          recipient_uuid: recipient.uuid,
          document_uuid: contract.documents.first.uuid,
          page: 1,
          x: 42,
          y: 64,
          width: 180,
          height: 64
        }
      }
    end

    assert_redirected_to contract_signature_field_preparations_path(contract)
    assert_equal I18n.t("contracts.signature_field_preparations.create.success"), flash[:notice]

    preparation = contract.reload.signature_field_preparations.last
    assert_equal recipient, preparation.recipient
    assert_equal contract.documents.first, preparation.document
    assert_equal 42.0, preparation.x.to_f
  end

  test "destroy removes a prepared signature field" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    preparation = nil

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      preparation = contract.signature_field_preparations.create!(
        recipient: recipient,
        document: contract.documents.first,
        page: 1,
        x: 42,
        y: 64,
        width: 180,
        height: 64
      )

      delete :destroy, params: { contract_id: contract.uuid, id: preparation.id }
    end

    assert_redirected_to contract_signature_field_preparations_path(contract)
    assert_equal I18n.t("contracts.signature_field_preparations.destroy.success"), flash[:notice]
    assert_not SignatureFieldPreparation.exists?(preparation.id)
  end

  test "finalize generates prepared signing pdf and redirects to bundle" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 1,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )

    with_autogram_service(fake_autogram_service(has_signatures: false, prepared_content: "prepared pdf content")) do
      post :finalize, params: { contract_id: contract.uuid }
    end

    assert_redirected_to bundle_path(contract.bundle)
    assert_equal I18n.t("contracts.signature_field_preparations.finalize.success"), flash[:notice]

    contract.reload
    assert_equal Contract::PREPARED_SIGNATURE_FIELDS_ORIGIN, contract.latest_content_version.origin
    assert_equal "prepared pdf content", contract.latest_content_version.content
    assert_not contract.signed_document_attached?
    assert_equal "prepared pdf content", contract.documents_to_sign.first.content
  end

  test "finalize prepares signature fields from latest source version" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    contract.add_signed_content_version!(
      content: "%PDF-1.4 visually stamped content",
      filename: "signature-field-test-visual.pdf",
      content_type: "application/pdf",
      origin: "visual"
    )
    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 1,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )
    service = fake_autogram_service(has_signatures: false, prepared_content: "prepared pdf content")

    with_autogram_service(service) do
      post :finalize, params: { contract_id: contract.uuid }
    end

    assert_redirected_to bundle_path(contract.bundle)
    assert_equal "%PDF-1.4 visually stamped content", service.last_document_content
  end

  test "create invalidates prepared signing pdf" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    second_recipient = contract.bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    contract.add_prepared_signature_fields_content_version!(
      content: "prepared pdf content",
      filename: "prepared.pdf",
      content_type: "application/pdf"
    )

    with_autogram_service(fake_autogram_service(has_signatures: false)) do
      post :create, params: {
        contract_id: contract.uuid,
        signature_field_preparation: {
          recipient_uuid: second_recipient.uuid,
          document_uuid: contract.documents.first.uuid,
          page: 1,
          x: 12,
          y: 24,
          width: 180,
          height: 64
        }
      }
    end

    assert_redirected_to contract_signature_field_preparations_path(contract)
    assert_not contract.reload.prepared_signature_fields_source_attached?
  end

  test "index links to editing for a placed field" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    preparation = contract.signature_field_preparations.create!(
      recipient: recipient, document: contract.documents.first, page: 1, x: 42, y: 64, width: 180, height: 64
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :success
    assert_select "a[href=?]", edit_contract_signature_field_preparation_path(contract, preparation)
  end

  test "edit prefills the placement form for an existing field" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    preparation = contract.signature_field_preparations.create!(
      recipient: recipient, document: contract.documents.first, page: 2, x: 42, y: 64, width: 180, height: 64
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      get :edit, params: { contract_id: contract.uuid, id: preparation.id }
    end

    assert_response :success
    assert_select "form[action=?]", contract_signature_field_preparation_path(contract, preparation) do
      assert_select "input[name='_method'][value='patch']"
      assert_select "input[name='signature_field_preparation[x]'][value='42.0']"
      assert_select "input[name='signature_field_preparation[page]'][value='2']"
      assert_select "select[name='signature_field_preparation[recipient_uuid]']", count: 0
    end
    assert_includes response.body, I18n.t("contracts.signature_field_preparations.index.form.editing_title")
    assert_includes response.body, recipient.display_name
  end

  test "update moves an existing field and invalidates the prepared signing pdf" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    preparation = contract.signature_field_preparations.create!(
      recipient: recipient, document: contract.documents.first, page: 1, x: 42, y: 64, width: 180, height: 64
    )
    contract.add_prepared_signature_fields_content_version!(
      content: "prepared pdf content", filename: "prepared.pdf", content_type: "application/pdf"
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      patch :update, params: {
        contract_id: contract.uuid,
        id: preparation.id,
        signature_field_preparation: { page: 3, x: 100, y: 200, width: 200, height: 70 }
      }
    end

    assert_redirected_to contract_signature_field_preparations_path(contract)
    assert_equal I18n.t("contracts.signature_field_preparations.update.success"), flash[:notice]

    preparation.reload
    assert_equal 3, preparation.page
    assert_equal 100.0, preparation.x.to_f
    assert_equal 200.0, preparation.y.to_f
    assert_equal 200.0, preparation.width.to_f
    assert_not contract.reload.prepared_signature_fields_source_attached?
  end

  test "update keeps the recipient and document of the edited field" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    other_recipient = contract.bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    preparation = contract.signature_field_preparations.create!(
      recipient: recipient, document: contract.documents.first, page: 1, x: 42, y: 64, width: 180, height: 64
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      patch :update, params: {
        contract_id: contract.uuid,
        id: preparation.id,
        signature_field_preparation: { x: 90, recipient_uuid: other_recipient.uuid, document_uuid: contract.documents.first.uuid }
      }
    end

    assert_redirected_to contract_signature_field_preparations_path(contract)

    preparation.reload
    assert_equal recipient, preparation.recipient
    assert_equal 90.0, preparation.x.to_f
  end

  test "update re-renders the edit form when the geometry is invalid" do
    contract, recipient = create_bundle_contract_with_recipient(author: @user)
    preparation = contract.signature_field_preparations.create!(
      recipient: recipient, document: contract.documents.first, page: 1, x: 42, y: 64, width: 180, height: 64
    )

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      patch :update, params: { contract_id: contract.uuid, id: preparation.id, signature_field_preparation: { width: 0 } }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]", contract_signature_field_preparation_path(contract, preparation)
    assert_equal 180.0, preparation.reload.width.to_f
  end

  test "non-author cannot manage signature field preparations" do
    contract, = create_bundle_contract_with_recipient(author: @user)
    other_user = users(:two)
    other_user.define_singleton_method(:accepted_current_policies?) { true }
    @controller.singleton_class.define_method(:current_user) { other_user }

    preparation = nil

    with_autogram_service(fake_validation_service(has_signatures: false)) do
      preparation = contract.signature_field_preparations.create!(
        recipient: contract.bundle.recipients.first,
        document: contract.documents.first,
        page: 1,
        x: 42,
        y: 64,
        width: 180,
        height: 64
      )

      get :index, params: { contract_id: contract.uuid }
      assert_response :forbidden

      get :edit, params: { contract_id: contract.uuid, id: preparation.id }
      assert_response :forbidden

      patch :update, params: { contract_id: contract.uuid, id: preparation.id, signature_field_preparation: { x: 10 } }
    end

    assert_response :forbidden
    assert_equal 42.0, preparation.reload.x.to_f
  end

  test "signed pades contract cannot manage signature field preparations" do
    contract, = create_bundle_contract_with_recipient(author: @user)
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed content",
      filename: "signed.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )

    with_autogram_service(fake_validation_service(has_signatures: true)) do
      get :index, params: { contract_id: contract.uuid }
    end

    assert_response :unprocessable_entity
  end

  private

  def create_bundle_contract_with_recipient(author:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "signature-field-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    bundle = Bundle.create!(author: author, contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")

    [ contract.reload, recipient ]
  end

  def fake_autogram_service(has_signatures:, prepared_content: nil)
    Struct.new(:validation_result, :prepared_content, :last_document_content) do
      def validate_signatures(_document)
        validation_result
      end

      def prepare_signature_fields(document, fields:)
        self.last_document_content = document.content
        prepared_content || "%PDF-1.4 prepared fields"
      end
    end.new(
      AutogramService::ValidationResult.new(
        hasSignatures: has_signatures,
        signatures: [],
        documentInfo: { signatureForm: "PAdES" }
      ),
      prepared_content
    )
  end

  alias_method :fake_validation_service, :fake_autogram_service

  def with_autogram_service(service)
    original_autogram_service = AutogramEnvironment.method(:autogram_service)
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { service }
    yield
  ensure
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
  end
end
