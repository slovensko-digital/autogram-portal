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
    contract = create_contract_with_documents(document_names: [ "contract-a.txt", "contract-b.txt" ])
    service = RecordingValidationService.new(
      "contract-a.txt" => AutogramService::ValidationResult.new(hasSignatures: false),
      "contract-b.txt" => AutogramService::ValidationResult.new(hasSignatures: false)
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_equal [ "contract-a.txt", "contract-b.txt" ], service.calls
    assert_equal [ "contract-a.txt", "contract-b.txt" ], @controller.instance_variable_get(:@validation_results).map(&:label)
    assert_includes response.body, I18n.t("shared.signature_validation.no_signatures_title")
  end

  test "validate shows coverage badges for signed multi document containers" do
    contract = create_contract_with_documents(
      document_names: [ "contract-a.txt", "contract-b.txt" ],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 6, 5, 10, 43, 47),
            signatureLevel: "BASELINE_T",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signedObjects: [
              { filename: "contract-a.txt" },
              { filename: "contract-b.txt" }
            ],
            unsignedObjects: [],
            timestampInfo: nil
          )
        ],
        documentInfo: {
          containerType: "ASiC_E",
          signatureForm: "XAdES",
          signedObjectsCount: 2,
          unsignedObjectsCount: 0,
          signedObjects: [
            { filename: "contract-a.txt" },
            { filename: "contract-b.txt" }
          ],
          unsignedObjects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_equal [ "contract-signed.asice" ], service.calls
    assert_select "span", text: I18n.t("shared.signature_validation.signature_qualifications.qesig"), count: 1
  end

  test "validate lists only covered documents when signature covers part of a multi document container" do
    contract = create_contract_with_documents(
      document_names: [ "contract-a.txt", "contract-b.txt" ],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 6, 5, 10, 43, 47),
            signatureLevel: "BASELINE_T",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signedObjects: [
              { filename: "contract-a.txt" }
            ],
            unsignedObjects: [
              { filename: "contract-b.txt" }
            ],
            timestampInfo: nil
          )
        ],
        documentInfo: {
          containerType: "ASiC_E",
          signatureForm: "XAdES",
          signedObjectsCount: 1,
          unsignedObjectsCount: 1,
          signedObjects: [
            { filename: "contract-a.txt" }
          ],
          unsignedObjects: [
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
    assert_select "span", text: I18n.t("shared.signature_validation.not_all_documents_covered"), count: 2
  end

  test "validate does not show coverage badges for single document signatures" do
    contract = Contract.new(
      allowed_methods: [ "qes" ],
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

    contract.add_signed_content_version!(
      content: "signed container content",
      filename: "contract-signed.asice",
      content_type: "application/vnd.etsi.asic-e+zip",
      origin: "uploaded_signed"
    )

    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 6, 5, 10, 43, 47),
            signatureLevel: "BASELINE_T",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "QESIG"
            },
            signedObjects: [
              { filename: "contract-a.txt" }
            ],
            unsignedObjects: [],
            timestampInfo: nil
          )
        ],
        documentInfo: {
          containerType: "ASiC_E",
          signatureForm: "XAdES",
          signedObjectsCount: 1,
          unsignedObjectsCount: 0,
          signedObjects: [
            { filename: "contract-a.txt" }
          ],
          unsignedObjects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_select "span", text: I18n.t("shared.signature_validation.all_documents_covered"), count: 0
    assert_select "span", text: I18n.t("shared.signature_validation.not_all_documents_covered"), count: 0
    assert_not_includes response.body, I18n.t("shared.signature_validation.not_all_documents_covered")
  end

  test "validate shows qualification badge adesig qc signatures" do
    contract = create_contract_with_documents(
      document_names: [ "contract-a.txt", "contract-b.txt" ],
      signed_document_name: "contract-signed.asice"
    )
    service = RecordingValidationService.new(
      "contract-signed.asice" => AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 6, 5, 10, 43, 47),
            signatureLevel: "BASELINE_T",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "ADESIG_QC-QC"
            },
            signedObjects: [
              { filename: "contract-a.txt" },
              { filename: "contract-b.txt" }
            ],
            unsignedObjects: [],
            timestampInfo: {
              count: 1,
              qualified: true,
              timestamps: [
                AutogramService::ValidationTimestamp.new(
                  type: "SIGNATURE_TIMESTAMP",
                  time: Time.utc(2026, 6, 5, 10, 43, 47),
                  qualification: "QTSA",
                  subject: "CN=Timestamp Authority"
                )
              ]
            }
          )
        ],
        documentInfo: {
          containerType: "ASiC_E",
          signatureForm: "XAdES",
          signedObjectsCount: 2,
          unsignedObjectsCount: 0,
          signedObjects: [
            { filename: "contract-a.txt" },
            { filename: "contract-b.txt" }
          ],
          unsignedObjects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_select "span", text: I18n.t("shared.signature_validation.signature_qualifications.adesig_qc_qc_ts"), count: 1
  end

  test "validate shows per-signature covered documents for multi-signature containers" do
    contract = create_contract_with_documents(
      document_names: [ "TextDocument.txt", "PdfDocument.pdf", "document.xdcf" ],
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
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 6, 2, 12, 25, 52),
            signatureLevel: "BASELINE_B",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "NA"
            },
            signedObjects: [
              { filename: "document.xdcf" },
              { filename: "PdfDocument.pdf" },
              { filename: "TextDocument.txt" }
            ],
            unsignedObjects: [],
            timestampInfo: nil
          ),
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 6, 2, 14, 11, 55),
            signatureLevel: "BASELINE_B",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: {
              subject: "CN=Autogram Test",
              issuer: "CN=Test Issuer",
              qualification: "NA"
            },
            signedObjects: [
              { filename: "PdfDocument.pdf" }
            ],
            unsignedObjects: [],
            timestampInfo: nil
          )
        ],
        documentInfo: {
          containerType: "ASiC_E",
          signatureForm: "XAdES",
          signedObjectsCount: 3,
          unsignedObjectsCount: 0,
          signedObjects: [
            { filename: "document.xdcf" },
            { filename: "PdfDocument.pdf" },
            { filename: "TextDocument.txt" }
          ],
          unsignedObjects: []
        }
      )
    )

    with_autogram_service(service) do
      get :validate, params: { id: contract.uuid }
    end

    assert_response :success
    assert_includes response.body, I18n.t("shared.signature_validation.all_documents_covered")
    assert_select "li", text: "PdfDocument.pdf", count: 1
  end

  private

  def create_contract_with_documents(document_names:, signed_document_name: nil)
    contract = Contract.new(
      allowed_methods: [ "qes" ],
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
    contract.reload

    if signed_document_name
      contract.add_signed_content_version!(
        content: "signed container content",
        filename: signed_document_name,
        content_type: "application/vnd.etsi.asic-e+zip",
        origin: "uploaded_signed"
      )
    elsif contract.signed_document_attached?
      contract.content_versions.destroy_all
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
