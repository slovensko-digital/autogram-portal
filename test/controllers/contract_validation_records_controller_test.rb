require "test_helper"

class ContractValidationRecordsControllerTest < ActionController::TestCase
  include ActiveJob::TestHelper

  tests ContractValidationRecordsController

  setup do
    @user = users(:one)
    @user.update_column(:features, [ "archivation" ])
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:enforce_current_policy_consent) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "index shows only current user's expiring records" do
    expiring_record = create_record(user: @user, expires_at: 1.month.from_now)
    create_record(user: @user, expires_at: 2.weeks.from_now, source_contract_uuid: expiring_record.source_contract_uuid, source_version_number: 0)
    create_record(user: @user, expires_at: 6.months.from_now)
    create_record(user: users(:two), expires_at: 1.month.from_now)

    get :index, params: { state: "expiring" }

    assert_response :success
    assert_equal [ expiring_record.id ], @controller.instance_variable_get(:@contract_validation_records).map(&:id)
  end

  test "index does not trigger live validation checks" do
    record = create_record(user: @user, expires_at: 1.month.from_now)
    contract = create_contract_with_version(user: @user)
    record.update!(contract: contract, contract_content_version: contract.latest_content_version, source_contract_uuid: contract.uuid, source_version_number: contract.latest_content_version.version_number)

    raising_service = Class.new do
      def validate_signatures(_document)
        raise "GET /contract_validation_records should not validate signed content"
      end
    end.new

    with_autogram_service(raising_service) do
      get :index
    end

    assert_response :success
  end

  test "destroy deletes current user's record" do
    record = create_record(user: @user, expires_at: 1.month.from_now)

    delete :destroy, params: { id: record.id }

    assert_redirected_to contract_validation_records_path
    assert_not ContractValidationRecord.exists?(record.id)
  end

  test "refresh enqueues archive refresh for refreshable current records" do
    ActiveJob::Base.queue_adapter = :test
    record = create_record(user: @user, expires_at: 1.month.from_now)
    contract = create_contract_with_version(user: @user)
    record.update!(contract: contract, contract_content_version: contract.latest_content_version, source_contract_uuid: contract.uuid, source_version_number: contract.latest_content_version.version_number)

    contract_content_version = contract.latest_content_version
    contract_validation_result = AutogramService::ValidationResult.new(
      hasSignatures: true,
      signatures: [
        AutogramService::ValidationSignature.new(
          signerName: "Autogram Test",
          signingTime: Time.current,
          signatureLevel: "BASELINE_T",
          validationResult: "TOTAL_PASSED",
          valid: true,
          certificateInfo: { qualification: "QESIG", notAfter: 1.month.from_now.iso8601 },
          timestampInfo: nil
        )
      ],
      documentInfo: { signedObjectsCount: 1, unsignedObjectsCount: 0, signedObjects: [], unsignedObjects: [] }
    )

    with_autogram_service(fake_validation_service(contract_validation_result)) do
      assert_enqueued_with(job: ContractValidationRecordRefreshJob, args: [ record.id ]) do
        post :refresh, params: { id: record.id }
      end
    end

    assert_redirected_to contract_validation_records_path
  ensure
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
  end

  test "index redirects to root without archivation feature" do
    @user.update_column(:features, [])

    get :index

    assert_redirected_to root_path
    assert_equal I18n.t("errors.archivation_disabled"), flash[:alert]
  end

  test "index shows AGP reference and mapping match for archived records" do
    contract = create_contract_with_version(user: @user)
    content_version = contract.latest_content_version

    record = ContractValidationRecord.create!(
      user: @user,
      contract: contract,
      contract_content_version: content_version,
      source_contract_uuid: contract.uuid,
      source_version_number: content_version.version_number,
      filename: "signed-contract.pdf",
      document_hash: Digest::SHA256.hexdigest("signed-pdf-content"),
      signature_levels: [ "BASELINE_T" ],
      signatures_count: 1,
      expires_at: 1.month.from_now,
      validation_details: {
        "signatures" => [
          { "agp_reference" => "PUBLIC-REF-123", "agp_instance" => "agp.example.test" }
        ]
      }
    )

    bundle = Bundle.create!(author: @user, contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)
    session = signer_contract.sessions.create!(
      type: "AdesEvidenceSession",
      signing_started_at: Time.current,
      options: { "verification_channel" => "sms" }
    )
    SignatureEvidenceRecord.create!(
      session: session,
      signer_contract: signer_contract,
      contract_content_version: content_version,
      public_reference: "PUBLIC-REF-123",
      state: "signed",
      canonical_payload: {}
    )

    get :index, params: { state: "all" }

    assert_response :success
    assert_select "a", text: "PUBLIC-REF-123", count: 1
    assert_includes response.body, "agp.example.test"
    assert_includes response.body, I18n.t("shared.signature_validation.agp_document_match")

    record.destroy!
  end

  private

  def create_record(user:, expires_at: nil, source_contract_uuid: SecureRandom.uuid, source_version_number: 1)
    ContractValidationRecord.create!(
      user: user,
      source_contract_uuid: source_contract_uuid,
      source_version_number: source_version_number,
      filename: "signed-contract.pdf",
      document_hash: Digest::SHA256.hexdigest(SecureRandom.hex(8)),
      signature_levels: [ "BASELINE_T" ],
      signatures_count: 1,
      expires_at: expires_at,
      validation_details: {}
    )
  end

  def create_contract_with_version(user:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "validation-record-controller.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      user: user,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    ).tap do |contract|
      contract.add_signed_content_version!(
        content: "signed-pdf-content",
        filename: "signed-contract.pdf",
        content_type: "application/pdf",
        origin: "uploaded_signed"
      )
    end
  end

  def fake_validation_service(validation_result)
    Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(validation_result)
  end

  def with_autogram_service(fake_service)
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:alias_method, :__original_autogram_service, :autogram_service)
    environment_singleton.send(:define_method, :autogram_service) { fake_service }

    yield
  ensure
    environment_singleton.send(:remove_method, :autogram_service)
    environment_singleton.send(:alias_method, :autogram_service, :__original_autogram_service)
    environment_singleton.send(:remove_method, :__original_autogram_service)
  end
end
