# == Schema Information
#
# Table name: contract_validation_records
#
#  id                                  :bigint           not null, primary key
#  document_hash                       :string           not null
#  expires_at                          :datetime
#  filename                            :string           not null
#  latest_archive_timestamp_expires_at :datetime
#  signature_levels                    :string           default([]), not null, is an Array
#  signatures_count                    :integer          default(0), not null
#  source_bundle_uuid                  :string
#  source_contract_uuid                :string           not null
#  source_version_number               :integer          not null
#  validation_details                  :jsonb            not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  contract_content_version_id         :bigint
#  contract_id                         :bigint
#  user_id                             :bigint           not null
#
# Indexes
#
#  idx_on_contract_content_version_id_7e3d0b9366                   (contract_content_version_id)
#  index_contract_validation_records_on_contract_id                (contract_id)
#  index_contract_validation_records_on_document_hash              (document_hash)
#  index_contract_validation_records_on_user_contract_and_version  (user_id,source_contract_uuid,source_version_number) UNIQUE
#  index_contract_validation_records_on_user_id                    (user_id)
#  index_contract_validation_records_on_user_id_and_expires_at     (user_id,expires_at)
#
# Foreign Keys
#
#  fk_rails_...  (contract_content_version_id => contract_content_versions.id) ON DELETE => nullify
#  fk_rails_...  (contract_id => contracts.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class ContractValidationRecordTest < ActiveSupport::TestCase
  test "capture uses the earliest relevant expiry when no archive timestamp is present" do
    contract = create_contract(user: users(:one))
    version = contract.add_signed_content_version!(
      content: "signed-pdf-content",
      filename: "contract-signed.pdf",
      content_type: "application/pdf",
      origin: "uploaded_signed"
    )

    record = ContractValidationRecord.capture!(
      contract: contract,
      contract_content_version: version,
      validation_result: validation_result(
        certificate_not_after: "2028-06-02T12:25:52 +0000",
        timestamps: [
          AutogramService::ValidationTimestamp.new(
            type: "SIGNATURE_TIMESTAMP",
            time: Time.parse("2026-06-02T12:26:52 +0000"),
            qualification: "QTS",
            subject: "CN=Timestamp Authority",
            notAfter: "2027-01-15T00:00:00 +0000"
          )
        ]
      ),
      signed_content: "signed-pdf-content",
      filename: "contract-signed.pdf"
    )

    assert_equal Time.parse("2027-01-15T00:00:00 +0000"), record.expires_at
    assert_nil record.latest_archive_timestamp_expires_at
    assert_equal "2028-06-02T12:25:52Z", record.validation_details.dig("signatures", 0, "certificate", "not_after")
  end

  test "capture prefers archive timestamp expiry and survives contract deletion" do
    contract = create_contract(user: users(:one))
    version = contract.add_signed_content_version!(
      content: "signed-pdf-content",
      filename: "contract-signed.pdf",
      content_type: "application/pdf",
      origin: "uploaded_signed"
    )

    record = ContractValidationRecord.capture!(
      contract: contract,
      contract_content_version: version,
      validation_result: validation_result(
        certificate_not_after: "2028-06-02T12:25:52 +0000",
        timestamps: [
          AutogramService::ValidationTimestamp.new(
            type: "ARCHIVE_TIMESTAMP",
            time: Time.parse("2026-06-02T12:26:52 +0000"),
            qualification: "QTS",
            subject: "CN=Timestamp Authority",
            notAfter: "2030-06-02T12:26:52 +0000"
          )
        ]
      ),
      signed_content: "signed-pdf-content",
      filename: "contract-signed.pdf"
    )

    contract.destroy!

    assert_nil record.reload.contract
    assert_equal Time.parse("2030-06-02T12:26:52 +0000"), record.expires_at
    assert_equal Time.parse("2030-06-02T12:26:52 +0000"), record.latest_archive_timestamp_expires_at
    assert_equal contract.uuid, record.source_contract_uuid
  end

  test "latest_per_contract returns only the newest record for each contract" do
    contract = create_contract(user: users(:one))
    old_version = contract.add_signed_content_version!(
      content: "signed-pdf-content-v1",
      filename: "contract-signed-v1.pdf",
      content_type: "application/pdf",
      origin: "uploaded_signed"
    )
    new_version = contract.add_signed_content_version!(
      content: "signed-pdf-content-v2",
      filename: "contract-signed-v2.pdf",
      content_type: "application/pdf",
      origin: "extension"
    )

    old_record = ContractValidationRecord.create!(
      user: users(:one),
      contract: contract,
      contract_content_version: old_version,
      source_contract_uuid: contract.uuid,
      source_version_number: 1,
      filename: old_version.filename,
      document_hash: Digest::SHA256.hexdigest("old"),
      signature_levels: [ "BASELINE_T" ],
      signatures_count: 1,
      expires_at: 1.month.from_now,
      validation_details: {}
    )
    new_record = ContractValidationRecord.create!(
      user: users(:one),
      contract: contract,
      contract_content_version: new_version,
      source_contract_uuid: contract.uuid,
      source_version_number: 2,
      filename: new_version.filename,
      document_hash: Digest::SHA256.hexdigest("new"),
      signature_levels: [ "BASELINE_LTA" ],
      signatures_count: 1,
      expires_at: 6.months.from_now,
      validation_details: {}
    )

    latest_ids = ContractValidationRecord.where(id: [ old_record.id, new_record.id ]).latest_per_contract.pluck(:id)

    assert_equal [ new_record.id ], latest_ids
  end

  private

  def create_contract(user: nil)
    user&.update_column(:features, [ "archivation" ])

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "validation-record-test.pdf",
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

  def validation_result(certificate_not_after:, timestamps: [])
    AutogramService::ValidationResult.new(
      hasSignatures: true,
      signatures: [
        AutogramService::ValidationSignature.new(
          signerName: "Autogram Test",
          signingTime: Time.parse("2026-06-02T12:25:52 +0000"),
          signatureLevel: "BASELINE_B",
          validationResult: "TOTAL_PASSED",
          valid: true,
          certificateInfo: {
            subject: "CN=Autogram Test",
            issuer: "CN=Issuer",
            qualification: "QESIG",
            notAfter: certificate_not_after
          },
          timestampInfo: {
            count: timestamps.length,
            qualified: timestamps.any?(&:qualified?),
            timestamps: timestamps
          }
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
  end
end
