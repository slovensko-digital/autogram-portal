require "test_helper"

class AvmDownloadSignedFileJobTest < ActiveJob::TestCase
  test "a rejected signed file fails the session with the reason for the signer" do
    session = create_avm_session
    avm_service = Struct.new(:document) do
      def download_signed_document(_document_identifier, _encryption_key)
        document
      end
    end.new(Base64.strict_encode64("signed"))
    validation_service = Struct.new(:result) do
      def validate_signatures(_document)
        result
      end
    end.new(AutogramService::ValidationResult.new(hasSignatures: false))

    with_autogram_service(validation_service) do
      assert_raises(UncaughtThrowError) { Avm::DownloadSignedFileJob.perform_now(session, avm_service: avm_service) }
    end

    assert session.reload.failed?
    assert_equal I18n.t("session.errors.no_signatures"), session.error_message
  end

  test "a failed download fails the session" do
    session = create_avm_session
    avm_service = Object.new
    avm_service.define_singleton_method(:download_signed_document) { |*| raise "connection reset" }

    assert_raises(UncaughtThrowError) { Avm::DownloadSignedFileJob.perform_now(session, avm_service: avm_service) }

    assert session.reload.failed?
    assert_equal "Stiahnutie podpísaného dokumentu zlyhalo: connection reset", session.error_message
  end

  test "a bundle signature completed another way meanwhile fails the session instead of signing again" do
    session = create_avm_session
    bundle = Bundle.create!(tenant: tenants(:one), contracts: [ session.contract ])
    signer_contract = bundle.recipients.create!(email: "signer@example.com", locale: "sk").signer_contracts.sole
    session.update!(signer_contract: signer_contract)
    signer_contract.update_column(:signed_at, 1.minute.ago) # e.g. the organization approved their scan signed on paper
    avm_service = Struct.new(:document) do
      def download_signed_document(_document_identifier, _encryption_key)
        document
      end
    end.new(Base64.strict_encode64("signed"))

    assert_raises(UncaughtThrowError) { Avm::DownloadSignedFileJob.perform_now(session, avm_service: avm_service) }

    assert session.reload.failed?
    assert_equal I18n.t("bundles.sign.signature_no_longer_required"), session.error_message
    assert_equal 0, session.contract.content_versions.count
  end

  private

  def create_avm_session
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "avm-test.pdf",
      content_type: "application/pdf"
    )
    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )

    AnonymousSigner.create!.signer_contracts.create!(contract: contract).sessions.create!(
      type: "AvmSession",
      signing_started_at: Time.current,
      options: { "document_identifier" => "guid-123", "encryption_key" => "secret-key-456" }
    )
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
