require "test_helper"

class ContractValidationRecordsMaintenanceJobTest < ActiveJob::TestCase
  test "enqueues refresh only for latest validation record per contract" do
    ActiveJob::Base.queue_adapter = :test

    contract = create_contract_with_versions
    old_record = create_record_for(contract: contract, version: contract.content_versions.last, source_version_number: 1)
    latest_record = create_record_for(contract: contract, version: contract.content_versions.first, source_version_number: 2)

    service = counting_validation_service

    with_autogram_service(service) do
      assert_enqueued_with(job: ContractValidationRecordRefreshJob, args: [ latest_record.id ]) do
        ContractValidationRecordsMaintenanceJob.perform_now
      end
    end

    enqueued_refresh_ids = enqueued_jobs
      .select { |job| job[:job] == ContractValidationRecordRefreshJob }
      .map { |job| job[:args].first }

    refute_includes enqueued_refresh_ids, old_record.id
  ensure
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
  end

  private

  def create_contract_with_versions
    users(:one).update_column(:features, [ "archivation" ])
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "maintenance-job-contract.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      user: users(:one),
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    ).tap do |contract|
      contract.add_signed_content_version!(
        content: "signed-v1",
        filename: "maintenance-job-contract-v1.pdf",
        content_type: "application/pdf",
        origin: "uploaded_signed"
      )
      contract.add_signed_content_version!(
        content: "signed-v2",
        filename: "maintenance-job-contract-v2.pdf",
        content_type: "application/pdf",
        origin: "extension"
      )
      contract.reload
    end
  end

  def create_record_for(contract:, version:, source_version_number:)
    ContractValidationRecord.create!(
      user: contract.user,
      contract: contract,
      contract_content_version: version,
      source_contract_uuid: contract.uuid,
      source_version_number: source_version_number,
      filename: version.filename,
      document_hash: Digest::SHA256.hexdigest(version.filename),
      signature_levels: [ "BASELINE_T" ],
      signatures_count: 1,
      expires_at: 1.month.from_now,
      validation_details: {
        "signatures" => [ { "valid" => true, "validation_result" => "TOTAL_PASSED" } ]
      }
    )
  end

  def counting_validation_service
    Struct.new(:calls) do
      def validate_signatures(_document)
        self.calls += 1
        AutogramService::ValidationResult.new(
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
      end
    end.new(0)
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
