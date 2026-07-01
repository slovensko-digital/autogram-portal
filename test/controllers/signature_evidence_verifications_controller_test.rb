require "test_helper"

class SignatureEvidenceVerificationsControllerTest < ActionDispatch::IntegrationTest
  test "show renders lookup form" do
    get signature_evidence_verification_path

    assert_response :success
    assert_select "form[action='#{signature_evidence_verification_path}'][method='get']"
    assert_select "input[name='reference']"
  end

  test "show renders public evidence details for matching reference" do
    evidence_record = create_public_evidence_record

    get signature_evidence_verification_path, params: { reference: evidence_record.public_reference }

    assert_response :success
    assert_includes response.body, evidence_record.public_reference
    assert_includes response.body, "Autogram Test"
    assert_includes response.body, "INDETERMINATE"
    assert_includes response.body, I18n.t("signature_evidence_verifications.show.evidence_seal_status_valid")
    assert_includes response.body, download_signature_evidence_verification_path(reference: evidence_record.public_reference)
  end

  test "download redirects to attached sealed evidence file" do
    evidence_record = create_public_evidence_record

    get download_signature_evidence_verification_path(reference: evidence_record.public_reference)

    assert_response :redirect
    assert_includes response.location, "/rails/active_storage/blobs/redirect/"
  end

  test "download falls back to stored manifest when attachment is missing" do
    evidence_record = create_public_evidence_record(attach_file: false)

    get download_signature_evidence_verification_path(reference: evidence_record.public_reference)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal evidence_record.signed_manifest, response.body
    assert_includes response.headers["Content-Disposition"], "attachment"
  end

  test "download returns not found when reference is unknown" do
    get download_signature_evidence_verification_path(reference: "missing-reference")

    assert_response :not_found
  end

  test "private download is forbidden for anonymous visitor" do
    evidence_record = create_public_evidence_record(attach_private_package: true)

    get download_private_signature_evidence_verification_path(reference: evidence_record.public_reference)

    assert_response :forbidden
  end

  test "private evidence is accessible to bundle author" do
    evidence_record = create_public_evidence_record(attach_private_package: true)

    assert evidence_record.private_evidence_accessible_by?(users(:one))
    assert_not evidence_record.private_evidence_accessible_by?(users(:two))
  end

  test "show renders not found state for unknown reference" do
    get signature_evidence_verification_path, params: { reference: "missing-reference" }

    assert_response :success
    assert_includes response.body, I18n.t("signature_evidence_verifications.show.not_found")
  end

  private

  def create_public_evidence_record(attach_file: true, attach_private_package: false)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 signed content"),
      filename: "verified.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.create!(
      allowed_methods: [ "ades" ],
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(
      email: "recipient-#{SecureRandom.hex(4)}@example.com",
      locale: "en",
      mobile_phone: "+421901234567"
    )
    signer_contract = recipient.recipient_signer.signer_contracts.find_by!(contract: contract)
    session = signer_contract.sessions.create!(
      type: "AdesEvidenceSession",
      signing_started_at: Time.current,
      status: :signed,
      options: { "verification_channel" => "sms" }
    )

    version = contract.add_signed_content_version!(
      content: "%PDF-1.4 signed output",
      filename: "verified-signed.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )

    canonical_payload = {
      "verification_channel" => "sms",
      "events" => [
        { "type" => "sms_verified", "occurred_at" => "2026-07-01T12:00:00Z", "details" => {} },
        { "type" => "server_signed", "occurred_at" => "2026-07-01T12:05:00Z", "details" => {} }
      ]
    }

    record = session.create_signature_evidence_record!(
      signer_contract: signer_contract,
      state: "signed",
      contract_content_version: version,
      canonical_payload: canonical_payload
    )
    sealed_manifest = build_signed_manifest(record, contract: contract, canonical_payload: canonical_payload)
    record.update!(
      signed_manifest: sealed_manifest,
      manifest_sha256: Digest::SHA256.hexdigest(sealed_manifest)
    )
    record.attach_sealed_evidence!(sealed_manifest) if attach_file
    record.attach_private_evidence_package!("private-evidence-package") if attach_private_package

    ContractValidationRecord.create!(
      user: users(:one),
      contract: contract,
      contract_content_version: version,
      source_contract_uuid: contract.uuid,
      source_version_number: version.version_number,
      filename: version.filename,
      document_hash: Digest::SHA256.hexdigest("%PDF-1.4 signed output"),
      signature_levels: [ "BASELINE_B" ],
      signatures_count: 1,
      validation_details: {
        "signatures" => [
          {
            "signer_name" => "Autogram Test",
            "signature_level" => "BASELINE_B",
            "validation_result" => "INDETERMINATE",
            "valid" => true,
            "certificate" => {
              "subject" => "CN=Autogram Test,O=Autogram Development",
              "issuer" => "CN=Autogram Test,O=Autogram Development",
              "qualification" => "NA",
              "not_after" => "2026-08-01T12:00:00Z"
            },
            "timestamps" => []
          }
        ]
      }
    )

    record
  end

  def build_signed_manifest(record, contract:, canonical_payload:)
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 5678
    certificate.subject = OpenSSL::X509::Name.parse("/CN=Autogram Test/O=Autogram Development")
    certificate.issuer = certificate.subject
    certificate.public_key = key.public_key
    certificate.not_before = 1.day.ago
    certificate.not_after = 30.days.from_now
    certificate.sign(key, OpenSSL::Digest::SHA256.new)

    unsigned_manifest = {
      "reference" => record.public_reference,
      "signed_at" => "2026-07-01T12:05:00Z",
      "signed_by" => "Autogram Test",
      "issued_by" => "Autogram Test",
      "verification_channel" => "sms",
      "contract_uuid" => contract.uuid,
      "evidence" => {
        "payload_sha256" => Digest::SHA256.hexdigest(JSON.generate(deep_sort_value(canonical_payload))),
        "canonical_payload" => deep_sort_value(canonical_payload)
      }
    }
    canonical_unsigned_manifest = JSON.generate(deep_sort_value(unsigned_manifest))
    signature = key.sign(OpenSSL::Digest::SHA256.new, canonical_unsigned_manifest)

    JSON.generate(
      deep_sort_value(
        unsigned_manifest.merge(
          "seal" => {
            "algorithm" => "RSASSA-PKCS1-v1_5-SHA256",
            "signed_json_sha256" => Digest::SHA256.hexdigest(canonical_unsigned_manifest),
            "signature" => Base64.strict_encode64(signature),
            "certificate" => {
              "pem" => certificate.to_pem,
              "sha256" => Digest::SHA256.hexdigest(certificate.to_der)
            }
          }
        )
      )
    )
  end

  def deep_sort_value(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) do |key, sorted|
        sorted[key] = deep_sort_value(value[key])
      end
    when Array
      value.map { |item| deep_sort_value(item) }
    else
      value
    end
  end
end
