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
require "tempfile"
require "zip"

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

  test "expands uploaded asice container into contract documents and preserves signed container" do
    contract = Contract.new(
      user: @user,
      documents: [ Document.new(blob: asice_blob("container.asice", {
        "contract-a.txt" => "alpha",
        "nested/contract-b.txt" => "beta",
        "META-INF/signatures.xml" => "<signature/>"
      })) ]
    )

    assert contract.save, contract.errors.full_messages.to_sentence
    assert contract.signed_document_attached?
    assert_equal "container.asice", contract.signed_document.filename.to_s
    assert_equal 1, contract.content_versions.count
    assert_equal [ "contract-a.txt", "contract-b.txt" ], contract.documents.map(&:filename).sort
    assert_equal "XAdES", contract.signature_parameters.format
  end

  test "expands pending uploaded asice container before the contract is saved" do
    uploaded_file = uploaded_asice_file("pending.asice", {
      "contract-a.txt" => "alpha",
      "mimetype" => "application/vnd.etsi.asic-e+zip",
      "document.xdcf" => "<xdcf></xdcf>",
      "nested/contract-b.pdf" => "%PDF-1.4 fake",
      "contract-b.txt" => "beta",
      "META-INF/signatures.xml" => "<signature/>"
    })

    contract = Contract.new(
      user: @user,
      documents: [ Document.new(blob: uploaded_file) ]
    )

    assert contract.save, contract.errors.full_messages.to_sentence
    assert contract.signed_document_attached?
    assert_equal "pending.asice", contract.signed_document.filename.to_s
    assert_equal 1, contract.content_versions.count
    assert_equal [ "contract-a.txt", "contract-b.pdf", "contract-b.txt", "document.xdcf" ], contract.documents.map(&:filename).sort
    xdcf_document = contract.documents.find { |document| document.filename == "document.xdcf" }
    assert_equal "application/vnd.gov.sk.xmldatacontainer+xml", xdcf_document.content_type
    assert_predicate xdcf_document.xdc_parameters, :present?
  ensure
    uploaded_file&.tempfile&.close!
  end

  test "extend_signatures creates a new content version without overwriting the previous one" do
    contract = Contract.create!(
      user: @user,
      documents_attributes: [ { blob: pdf_blob("original.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    initial_version = contract.add_signed_content_version!(
      content: "signed v1",
      filename: "original-signed.pdf",
      content_type: "application/pdf",
      origin: "uploaded_signed"
    )

    fake_service = Struct.new(:extended_content) do
      def validate_signatures(_document)
        AutogramService::ValidationResult.new(
          hasSignatures: true,
          signatures: [
            AutogramService::ValidationSignature.new(
              signerName: "Autogram Test",
              signingTime: Time.current,
              signatureLevel: "BASELINE_T",
              validationResult: "TOTAL_PASSED",
              valid: true,
              certificateInfo: {
                qualification: "QESIG",
                notAfter: 1.year.from_now.iso8601
              },
              timestampInfo: nil
            )
          ],
          documentInfo: {
            signedObjectsCount: 1,
            unsignedObjectsCount: 0,
            signedObjects: [],
            unsignedObjects: []
          }
        )
      end

      def extend_signatures(_document, target_level:)
        extended_content
      end
    end.new("signed v2")
    with_autogram_service(fake_service) do
      contract.extend_signatures!(target_level: "LTA", source_content_version: initial_version)

      contract.reload
      assert_equal 2, contract.content_versions.count
      assert_equal "signed v1", initial_version.reload.content
      assert_equal "signed v2", contract.latest_content_version.content
    end
  end

  test "pades_signed returns true only for signed pades content versions" do
    contract = Contract.create!(
      user: @user,
      documents_attributes: [ { blob: pdf_blob("original.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed",
      filename: "original-signed.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )

    fake_service = Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(AutogramService::ValidationResult.new(hasSignatures: true, documentInfo: { signatureForm: "PAdES" }))

    with_autogram_service(fake_service) do
      assert contract.pades_signed?
      assert_not contract.visual_signing_allowed?
    end
  end

  test "pades field preparation is allowed for unsigned bundled pades contracts" do
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("bundle-contract.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    Bundle.create!(author: @user, contracts: [ contract ])

    fake_service = Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(AutogramService::ValidationResult.new(hasSignatures: false, documentInfo: { signatureForm: "PAdES" }))

    with_autogram_service(fake_service) do
      assert contract.reload.pades_field_preparation_allowed?
    end
  end

  test "pades field preparation is not allowed for standalone contracts" do
    contract = Contract.create!(
      user: @user,
      documents_attributes: [ { blob: pdf_blob("standalone.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )

    fake_service = Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(AutogramService::ValidationResult.new(hasSignatures: false, documentInfo: { signatureForm: "PAdES" }))

    with_autogram_service(fake_service) do
      assert_not contract.pades_field_preparation_allowed?
    end
  end

  test "pades field preparation is allowed only for the bundle author" do
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("bundle-author.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    bundle = Bundle.create!(author: @user, contracts: [ contract ])
    other_user = users(:two)

    fake_service = Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(AutogramService::ValidationResult.new(hasSignatures: false, documentInfo: { signatureForm: "PAdES" }))

    with_autogram_service(fake_service) do
      assert contract.reload.pades_field_preparation_allowed_for?(bundle.author)
      assert_not contract.pades_field_preparation_allowed_for?(other_user)
      assert_not contract.pades_field_preparation_allowed_for?(nil)
    end
  end

  test "prepared signature fields source is used for signing without marking contract signed" do
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("bundle-author.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    Bundle.create!(author: @user, contracts: [ contract ])

    contract.add_prepared_signature_fields_content_version!(
      content: "%PDF-1.4 prepared source",
      filename: "bundle-author-prepared-fields.pdf",
      content_type: "application/pdf"
    )

    assert contract.source_document_attached?
    assert contract.prepared_signature_fields_source_attached?
    assert_not contract.signed_document_attached?
    assert_equal "%PDF-1.4 prepared source", contract.documents_to_sign.first.content
  end

  private

  def pdf_blob(filename, content)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: filename,
      content_type: "application/pdf"
    )
  end

  def asice_blob(filename, entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end

    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(buffer.string),
      filename: filename,
      content_type: "application/vnd.etsi.asic-e+zip"
    )
  end

  def uploaded_asice_file(filename, entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end

    tempfile = Tempfile.new([ File.basename(filename, ".asice"), ".asice" ])
    tempfile.binmode
    tempfile.write(buffer.string)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: "application/vnd.etsi.asic-e+zip"
    )
  end

  def with_autogram_service(service)
    original_autogram_service = AutogramEnvironment.method(:autogram_service)
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { service }
    yield
  ensure
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
  end
end
