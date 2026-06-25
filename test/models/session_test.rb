# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default("pending"), not null
#  type               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  index_sessions_on_signer_contract_id  (signer_contract_id)
#  index_sessions_on_type                (type)
#
# Foreign Keys
#
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "keeps iframe open while public bundle still has unsigned contracts" do
    contract_one = create_contract
    contract_two = create_contract
    Bundle.create!(author: users(:one), contracts: [ contract_one, contract_two ], publicly_visible: true)
    attach_signed_document(contract_one)

    session = create_session_for(contract_one, options: { "iframe" => "true" })

    assert_equal 2, session.bundle_contracts_total
    assert_equal 1, session.remaining_bundle_contracts_count
    assert_not session.bundle_signing_complete?
    assert session.inline_bundle_success?
    assert_not session.close_iframe_after_completion?
    assert_equal false, session.completion_event_payload[:close_iframe]
  end

  test "closes iframe when public single-contract bundle is fully signed" do
    contract = create_contract
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ], publicly_visible: true)
    attach_signed_document(contract)

    session = create_session_for(contract, options: { "iframe" => "true" })

    assert_equal 1, session.bundle_contracts_total
    assert_equal 0, session.remaining_bundle_contracts_count
    assert session.bundle_signing_complete?
    assert_not session.inline_bundle_success?
    assert session.close_iframe_after_completion?
    assert_equal bundle.uuid, session.completion_event_payload[:bundle_id]
    assert_equal true, session.completion_event_payload[:bundle_completed]
  end

  test "accept_signed_file persists validation metadata for authored contracts" do
    users(:one).update_column(:features, [ "archivation" ])
    contract = create_contract(user: users(:one))
    session = create_session_for(contract)
    validation_result = AutogramService::ValidationResult.new(
      hasSignatures: true,
      signatures: [
        AutogramService::ValidationSignature.new(
          signerName: "Autogram Test",
          signingTime: Time.parse("2026-06-02T12:25:52 +0000"),
          signatureLevel: "BASELINE_T",
          validationResult: "TOTAL_PASSED",
          valid: true,
          certificateInfo: {
            subject: "CN=Autogram Test",
            issuer: "CN=Issuer",
            qualification: "QESIG",
            notAfter: "2028-06-02T12:25:52 +0000"
          },
          timestampInfo: nil
        )
      ],
      documentInfo: {
        containerType: nil,
        signatureForm: "PAdES",
        signedObjectsCount: 1,
        unsignedObjectsCount: 0,
        signedObjects: [],
        unsignedObjects: []
      }
    )

    with_autogram_service(fake_validation_service(validation_result)) do
      session.accept_signed_file(Base64.strict_encode64("signed pdf content"))
    end

    record = ContractValidationRecord.find_by!(source_contract_uuid: contract.uuid)

    assert_equal users(:one), record.user
    assert_equal "session-test-signed.pdf", record.filename
    assert_equal Digest::SHA256.hexdigest("signed pdf content"), record.document_hash
    assert_equal [ "BASELINE_T" ], record.signature_levels
    assert_equal "AutogramSession", record.validation_details["captured_via"]
    assert_equal 1, record.source_version_number
    assert_equal 1, contract.reload.content_versions.count
  end

  test "accept_signed_file does not persist validation metadata when archivation is disabled" do
    contract = create_contract(user: users(:one))
    session = create_session_for(contract)
    validation_result = AutogramService::ValidationResult.new(
      hasSignatures: true,
      signatures: [
        AutogramService::ValidationSignature.new(
          signerName: "Autogram Test",
          signingTime: Time.parse("2026-06-02T12:25:52 +0000"),
          signatureLevel: "BASELINE_T",
          validationResult: "TOTAL_PASSED",
          valid: true,
          certificateInfo: {
            subject: "CN=Autogram Test",
            issuer: "CN=Issuer",
            qualification: "QESIG",
            notAfter: "2028-06-02T12:25:52 +0000"
          },
          timestampInfo: nil
        )
      ],
      documentInfo: {
        containerType: nil,
        signatureForm: "PAdES",
        signedObjectsCount: 1,
        unsignedObjectsCount: 0,
        signedObjects: [],
        unsignedObjects: []
      }
    )

    with_autogram_service(fake_validation_service(validation_result)) do
      session.accept_signed_file(Base64.strict_encode64("signed pdf content"))
    end

    assert_nil ContractValidationRecord.find_by(source_contract_uuid: contract.uuid)
  end

  private

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

  def create_contract(user: nil)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "session-test.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      user: user,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
  end

  def create_session_for(contract, options: nil)
    signer = AnonymousSigner.create!
    signer_contract = signer.signer_contracts.create!(contract: contract)
    signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current,
      options: options
    )
  end

  def attach_signed_document(contract)
    contract.add_signed_content_version!(
      content: "signed pdf content",
      filename: "signed.pdf",
      content_type: "application/pdf",
      origin: "uploaded_signed"
    )
  end
end
