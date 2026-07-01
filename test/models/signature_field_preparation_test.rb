# == Schema Information
#
# Table name: signature_field_preparations
#
#  id               :bigint           not null, primary key
#  field_identifier :string           not null
#  height           :decimal(10, 2)   not null
#  page             :integer          default(1), not null
#  width            :decimal(10, 2)   not null
#  x                :decimal(10, 2)   not null
#  y                :decimal(10, 2)   not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  contract_id      :bigint           not null
#  document_id      :bigint           not null
#  recipient_id     :bigint           not null
#
# Indexes
#
#  idx_signature_fields_on_recipient_contract_document     (recipient_id,contract_id,document_id) UNIQUE
#  index_signature_field_preparations_on_contract_id       (contract_id)
#  index_signature_field_preparations_on_document_id       (document_id)
#  index_signature_field_preparations_on_field_identifier  (field_identifier) UNIQUE
#  index_signature_field_preparations_on_recipient_id      (recipient_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (document_id => documents.id)
#  fk_rails_...  (recipient_id => recipients.id)
#
require "test_helper"

class SignatureFieldPreparationTest < ActiveSupport::TestCase
  test "is valid for unsigned bundled pades contract" do
    contract, recipient = create_bundle_pades_contract_with_recipient

    with_autogram_service(fake_validation_service(has_signatures: false, signature_form: "PAdES")) do
      preparation = SignatureFieldPreparation.new(
        contract: contract,
        document: contract.documents.first,
        recipient: recipient,
        page: 1,
        x: 40,
        y: 60,
        width: 180,
        height: 64
      )

      assert preparation.valid?, preparation.errors.full_messages.to_sentence
      assert preparation.field_identifier.present?
    end
  end

  test "requires unique recipient per contract document" do
    contract, recipient = create_bundle_pades_contract_with_recipient

    with_autogram_service(fake_validation_service(has_signatures: false, signature_form: "PAdES")) do
      SignatureFieldPreparation.create!(
        contract: contract,
        document: contract.documents.first,
        recipient: recipient,
        page: 1,
        x: 40,
        y: 60,
        width: 180,
        height: 64
      )

      duplicate = SignatureFieldPreparation.new(
        contract: contract,
        document: contract.documents.first,
        recipient: recipient,
        page: 1,
        x: 80,
        y: 80,
        width: 180,
        height: 64
      )

      assert_not duplicate.valid?
      assert duplicate.errors[:recipient_id].any?
    end
  end

  test "rejects contracts that already have cryptographic signatures" do
    contract, recipient = create_bundle_pades_contract_with_recipient
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed content",
      filename: "signed.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )

    with_autogram_service(fake_validation_service(has_signatures: true, signature_form: "PAdES")) do
      preparation = SignatureFieldPreparation.new(
        contract: contract,
        document: contract.documents.first,
        recipient: recipient,
        page: 1,
        x: 40,
        y: 60,
        width: 180,
        height: 64
      )

      assert_not preparation.valid?
      assert preparation.errors[:contract].any?
    end
  end

  private

  def create_bundle_pades_contract_with_recipient
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
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")

    [ contract.reload, recipient ]
  end

  def fake_validation_service(has_signatures:, signature_form: nil)
    Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(
      AutogramService::ValidationResult.new(
        hasSignatures: has_signatures,
        signatures: [],
        documentInfo: { signatureForm: signature_form }
      )
    )
  end

  def with_autogram_service(fake_service)
    original_autogram_service = AutogramEnvironment.method(:autogram_service)
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { fake_service }
    yield
  ensure
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
  end
end
