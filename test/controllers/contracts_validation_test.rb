require "test_helper"

class ContractsValidationTest < ActionController::TestCase
  tests ContractsController

  setup do
    user = users(:one)
    user.define_singleton_method(:accepted_current_policies?) { true }
    user.define_singleton_method(:locale) { "en" }

    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "validate renders each document separately for multi document contracts" do
    contract = create_contract_with_documents(document_names: ["contract-a.txt", "contract-b.txt"])
    service = RecordingValidationService.new(
      "contract-a.txt" => AutogramService::ValidationResult.new(hasSignatures: false),
      "contract-b.txt" => AutogramService::ValidationResult.new(hasSignatures: false)
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_equal ["contract-a.txt", "contract-b.txt"], service.calls
    assert_equal ["contract-a.txt", "contract-b.txt"], @controller.instance_variable_get(:@validation_results).map(&:label)
    assert_includes response.body, I18n.t("shared.signature_validation.no_signatures_title")
  end

  test "validate shows coverage badges for signed multi document containers" do
    contract = create_contract_with_documents(
      document_names: ["contract-a.txt", "contract-b.txt"],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 5, 10, 43, 47),
            signature_level: "BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signed_objects: [
              { filename: "contract-a.txt" },
              { filename: "contract-b.txt" }
            ],
            unsigned_objects: [],
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 2,
          unsigned_objects_count: 0,
          signed_objects: [
            { filename: "contract-a.txt" },
            { filename: "contract-b.txt" }
          ],
          unsigned_objects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_equal ["contract-signed.asice"], service.calls
    assert_includes response.body, I18n.t("shared.signature_validation.all_documents_covered")
    assert_includes response.body, I18n.t("shared.signature_validation.valid")
    assert_select "span[data-signature-badge='coverage']", count: 2
    assert_select "span[data-signature-badge='valid']", count: 1
    assert_select "span[data-signature-badge='qualification']", text: I18n.t("helpers.application.signature_qualifications.qesig"), count: 1
  end

  test "validate lists only covered documents when signature covers part of a multi document container" do
    contract = create_contract_with_documents(
      document_names: ["contract-a.txt", "contract-b.txt"],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 5, 10, 43, 47),
            signature_level: "BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signed_objects: [
              { filename: "contract-a.txt" }
            ],
            unsigned_objects: [
              { filename: "contract-b.txt" }
            ],
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 1,
          unsigned_objects_count: 1,
          signed_objects: [
            { filename: "contract-a.txt" }
          ],
          unsigned_objects: [
            { filename: "contract-b.txt" }
          ]
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_includes response.body, I18n.t("shared.signature_validation.covered_documents")
    assert_not_includes response.body, I18n.t("shared.signature_validation.all_documents_covered")
    assert_includes response.body, I18n.t("shared.signature_validation.not_all_documents_covered")
    assert_select "span[data-signature-badge='coverage']", count: 0
    assert_select "span[data-signature-badge='partial-coverage']", count: 2
  end

  test "validate does not show coverage badges for single document signatures" do
    contract = Contract.new(
      allowed_methods: ["qes"],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "XAdES"
      }
    )
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("contract-a.txt content"),
      filename: "contract-a.txt",
      content_type: "text/plain"
    )
    contract.documents.build(blob: blob)
    contract.save!

    signed_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("signed container content"),
      filename: "contract-signed.asice",
      content_type: "application/vnd.etsi.asic-e+zip"
    )
    contract.signed_document.attach(signed_blob)

    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 5, 10, 43, 47),
            signature_level: "BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signed_objects: [
              { filename: "contract-a.txt" }
            ],
            unsigned_objects: [],
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 1,
          unsigned_objects_count: 0,
          signed_objects: [
            { filename: "contract-a.txt" }
          ],
          unsigned_objects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_select "span[data-signature-badge='coverage']", count: 0
    assert_select "span[data-signature-badge='partial-coverage']", count: 0
    assert_not_includes response.body, I18n.t("shared.signature_validation.not_all_documents_covered")
  end

  test "validate treats matching asice object paths as covered documents" do
    contract = create_contract_with_documents(
      document_names: ["contract-a.txt", "contract-b.txt"],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 5, 10, 43, 47),
            signature_level: "BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signed_objects: [
              { path: "attachments/contract-a.txt" },
              { path: "nested/contracts/contract-b.txt" }
            ],
            unsigned_objects: [],
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 2,
          unsigned_objects_count: 0,
          signed_objects: [
            { filename: "contract-a.txt" },
            { filename: "contract-b.txt" }
          ],
          unsigned_objects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_select "span[data-signature-badge='coverage']", count: 2
  end

  test "validate shows qualification and timestamp badges without valid badge for non qualified signatures" do
    contract = create_contract_with_documents(
      document_names: ["contract-a.txt", "contract-b.txt"],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 5, 10, 43, 47),
            signature_level: "BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "ADESIG_QC-QC"
            },
            signed_objects: [
              { filename: "contract-a.txt" },
              { filename: "contract-b.txt" }
            ],
            unsigned_objects: [],
            timestamp_info: {
              count: 1,
              qualified: true,
              timestamps: [
                {
                  type: "SIGNATURE_TIMESTAMP",
                  time: Time.utc(2026, 6, 5, 10, 43, 47),
                  qualification: "QTSA",
                  subject: "CN=Timestamp Authority"
                }
              ]
            }
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 2,
          unsigned_objects_count: 0,
          signed_objects: [
            { filename: "contract-a.txt" },
            { filename: "contract-b.txt" }
          ],
          unsigned_objects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_select "span[data-signature-badge='valid']", count: 0
    assert_select "span[data-signature-badge='invalid']", count: 0
    assert_select "span[data-signature-badge='qualification']", text: I18n.t("helpers.application.signature_qualifications.adesig_qc_qc"), count: 1
    assert_select "span[data-signature-badge='timestamp']", text: I18n.t("shared.signature_validation.timestamp"), count: 1
  end

  test "validate falls back to container-level signed objects when signature coverage is omitted" do
    contract = create_contract_with_documents(
      document_names: ["contract-a.txt", "contract-b.txt"],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 5, 10, 43, 47),
            signature_level: "BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signed_objects: [],
            unsigned_objects: [],
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 1,
          unsigned_objects_count: 1,
          signed_objects: [
            { filename: "contract-a.txt" }
          ],
          unsigned_objects: [
            { filename: "contract-b.txt" }
          ]
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_includes response.body, I18n.t("shared.signature_validation.covered_documents")
    assert_includes response.body, "contract-a.txt"
    assert_not_includes response.body, I18n.t("shared.signature_validation.all_documents_covered")
  end

  test "validate shows per-signature covered documents for multi-signature containers" do
    contract = create_contract_with_documents(
      document_names: ["TextDocument.txt", "PdfDocument.pdf", "document.xdcf"],
      signed_document_name: "contract-signed.asice"
    )
    pdf_blob = contract.documents.find { |document| document.filename == "PdfDocument.pdf" }.blob
    pdf_blob.update!(content_type: "application/pdf")
    xdcf_blob = contract.documents.find { |document| document.filename == "document.xdcf" }.blob
    xdcf_blob.update!(content_type: "application/vnd.gov.sk.xmldatacontainer+xml")

    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 2, 12, 25, 52),
            signature_level: "BASELINE_B",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "NA"
            },
            signed_objects: [
              { filename: "document.xdcf" },
              { filename: "PdfDocument.pdf" },
              { filename: "TextDocument.txt" }
            ],
            unsigned_objects: [],
            timestamp_info: nil
          },
          {
            signer_name: "Autogram Test",
            signing_time: Time.utc(2026, 6, 2, 14, 11, 55),
            signature_level: "BASELINE_B",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "NA"
            },
            signed_objects: [
              { filename: "PdfDocument.pdf" }
            ],
            unsigned_objects: [],
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: "ASiC_E",
          signature_form: "XAdES",
          signed_objects_count: 3,
          unsigned_objects_count: 0,
          signed_objects: [
            { filename: "document.xdcf" },
            { filename: "PdfDocument.pdf" },
            { filename: "TextDocument.txt" }
          ],
          unsigned_objects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_select "span[data-signature-badge='coverage']", count: 2
    assert_includes response.body, I18n.t("shared.signature_validation.all_documents_covered")
    assert_select "li", text: "PdfDocument.pdf", count: 1
  end

  private

  def create_contract_with_documents(document_names:, signed_document_name: nil)
    contract = Contract.new(
      allowed_methods: ["qes"],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: document_names.length > 1 ? "XAdES" : "PAdES"
      }
    )

    document_names.each do |document_name|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("#{document_name} content"),
        filename: document_name,
        content_type: "text/plain"
      )

      contract.documents.build(blob: blob)
    end

    contract.save!

    if signed_document_name
      signed_blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("signed container content"),
        filename: signed_document_name,
        content_type: "application/vnd.etsi.asic-e+zip"
      )
      contract.signed_document.attach(signed_blob)
    end

    contract
  end

  def with_autogram_service(service)
    original_autogram_service = AutogramEnvironment.method(:autogram_service)
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { service }
    yield
  ensure
    AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
  end

  class RecordingValidationService
    attr_reader :calls

    def initialize(results_by_filename)
      @results_by_filename = results_by_filename
      @calls = []
    end

    def validate_signatures(document)
      filename = document.filename
      @calls << filename
      @results_by_filename.fetch(filename) do
        AutogramService::ValidationResult.new(hasSignatures: false)
      end
    end
  end
end
