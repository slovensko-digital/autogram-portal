require "test_helper"

class AdesServerSigningServiceTest < ActiveSupport::TestCase
  test "sign! requests detached data, signs it, and finalizes evidence" do
    session = create_verified_ades_session
    accepted_payload = nil
    session.define_singleton_method(:accept_signed_file) do |payload|
      accepted_payload = payload
      update!(status: :signed)
    end

    fake_avm_service = Class.new do
      attr_reader :requested_certificate, :received_signed_data, :requested_reference, :built_reference,
                  :requested_instance, :built_instance,
                  :evidence_requested_certificate, :evidence_sign_request_body, :evidence_built_sign_request_body,
                  :evidence_received_signed_data

      def request_data_to_sign(_contract, signer_contract: nil, signing_certificate:, signature_reference: nil, signature_instance: nil)
        @requested_certificate = signing_certificate
        @requested_reference = signature_reference
        @requested_instance = signature_instance
        { data_to_sign: Base64.strict_encode64("payload-to-sign"), signing_time: 1_783_000_000_000, signing_certificate: signing_certificate }
      end

      def build_signed_document(_contract, signer_contract: nil, data_to_sign_structure:, signed_data:, signature_reference: nil, signature_instance: nil)
        @received_signed_data = signed_data
        @built_reference = signature_reference
        @built_instance = signature_instance
        Base64.strict_encode64("signed-document")
      end

      def build_detached_sign_request_payload(filename:, content:, content_type:, level:, container: nil, packaging: nil, signature_reference: nil)
        {
          document: {
            content: Base64.strict_encode64(content),
            filename: filename
          },
          parameters: {
            level: level,
            container: container,
            packaging: packaging,
            signatureReference: signature_reference
          }.compact,
          payloadMimeType: "#{content_type};base64"
        }
      end

      def request_data_to_sign_from_request(sign_request_body:, signing_certificate:)
        @evidence_sign_request_body = sign_request_body
        @evidence_requested_certificate = signing_certificate
        { data_to_sign: Base64.strict_encode64("evidence-to-sign"), signing_time: 1_783_000_000_001, signing_certificate: signing_certificate }
      end

      def build_signed_document_from_request(sign_request_body:, data_to_sign_structure:, signed_data:)
        @evidence_built_sign_request_body = sign_request_body
        @evidence_received_signed_data = signed_data
        Base64.strict_encode64("signed-evidence-asice")
      end
    end.new

    credential = build_test_credential

    service = AdesServerSigningService.new(
      avm_service: fake_avm_service,
      clock: -> { Time.zone.parse("2026-07-01 13:00:00") },
      credential_loader: -> { credential }
    )

    service.sign!(session: session, ip_address: "127.0.0.1", user_agent: "Rails Test", app_host: "agp.example.test")

    assert_equal Base64.strict_encode64("signed-document"), accepted_payload
    assert_equal credential.encoded_certificate, fake_avm_service.requested_certificate
    assert_equal session.signature_evidence_record.public_reference, fake_avm_service.requested_reference
    assert_equal session.signature_evidence_record.public_reference, fake_avm_service.built_reference
    assert_equal "agp.example.test", fake_avm_service.requested_instance
    assert_equal "agp.example.test", fake_avm_service.built_instance
    assert_equal Base64.strict_encode64(credential.sign_bytes("payload-to-sign")), fake_avm_service.received_signed_data
    assert_equal credential.encoded_certificate, fake_avm_service.evidence_requested_certificate
    assert_equal Base64.strict_encode64(credential.sign_bytes("evidence-to-sign")), fake_avm_service.evidence_received_signed_data

    evidence_record = session.signature_evidence_record.reload
    assert_equal "signed", evidence_record.state
    assert_not_nil evidence_record.locked_at
    assert_equal Digest::SHA256.hexdigest(evidence_record.signed_manifest), evidence_record.manifest_sha256
    assert_equal 4, evidence_record.canonical_payload.fetch("events").size
    assert evidence_record.sealed_evidence.attached?
    assert evidence_record.private_evidence_package.attached?
    assert_equal :valid, evidence_record.evidence_seal_summary[:status]

    manifest = evidence_record.signed_manifest_payload
    assert_equal evidence_record.public_reference, manifest["reference"]
    assert_equal evidence_record.payload_sha256, manifest.dig("evidence", "payload_sha256")
    assert_equal session.contract.uuid, manifest["contract_uuid"]
    assert_equal "agp.example.test", manifest.dig("signature", "instance_host")
    assert_equal Digest::SHA256.hexdigest("signed-document"), manifest.dig("documents", "signed_document", "sha256")

    cert = OpenSSL::X509::Certificate.new(manifest.dig("seal", "certificate", "pem"))
    unsigned_manifest = manifest.except("seal")
    canonical_unsigned_manifest = canonical_json(unsigned_manifest)
    signature = Base64.strict_decode64(manifest.dig("seal", "signature"))

    assert_equal Digest::SHA256.hexdigest(canonical_unsigned_manifest), manifest.dig("seal", "signed_json_sha256")
    assert cert.public_key.verify(OpenSSL::Digest::SHA256.new, signature, canonical_unsigned_manifest)
    assert_equal evidence_record.signed_manifest, evidence_record.sealed_evidence.download

    assert_equal "signed-evidence-asice", evidence_record.private_evidence_package.download
    assert_equal fake_avm_service.evidence_sign_request_body, fake_avm_service.evidence_built_sign_request_body
    assert_equal "text/plain;base64", fake_avm_service.evidence_sign_request_body.fetch(:payloadMimeType)
    assert_equal "XAdES_BASELINE_B", fake_avm_service.evidence_sign_request_body.dig(:parameters, :level)
    assert_equal "ASiC_E", fake_avm_service.evidence_sign_request_body.dig(:parameters, :container)
    assert_equal "DETACHED", fake_avm_service.evidence_sign_request_body.dig(:parameters, :packaging)
    assert_nil fake_avm_service.evidence_sign_request_body.dig(:parameters, :signatureReference)
    assert_equal "signature-evidence-#{evidence_record.public_reference}.txt", fake_avm_service.evidence_sign_request_body.dig(:document, :filename)

    evidence_txt = Base64.strict_decode64(fake_avm_service.evidence_sign_request_body.dig(:document, :content))

    assert_includes evidence_txt, "AGP signature evidence"
    assert_includes evidence_txt, "reference: #{evidence_record.public_reference}"
    assert_includes evidence_txt, "signature.instance_host: agp.example.test"
    assert_includes evidence_txt, "recipient.mobile_phone: +421901234567"
    assert_includes evidence_txt, "verification.provider_request_id: req-1"
    assert_includes evidence_txt, "verification.last_request_ip: 127.0.0.1"
    assert_includes evidence_txt, "documents.signed_document.sha256: #{Digest::SHA256.hexdigest("signed-document")}"
  end

  test "sign! requires verified session" do
    session = create_ades_session
    error = assert_raises(AdesServerSigningService::VerificationRequiredError) do
      AdesServerSigningService.new(
        avm_service: Object.new,
        credential_loader: -> { raise "should not load" }
      ).sign!(session: session, ip_address: "127.0.0.1", user_agent: "Rails Test")
    end

    assert_equal I18n.t("contracts.sessions.ades_evidence.errors.not_verified"), error.message
  end

  private

  def canonical_json(value)
    JSON.generate(deep_sort_value(value))
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

  def build_test_credential
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1234
    certificate.subject = OpenSSL::X509::Name.parse("/CN=Autogram Test/O=Autogram Development")
    certificate.issuer = certificate.subject
    certificate.public_key = key.public_key
    certificate.not_before = 1.day.ago
    certificate.not_after = 30.days.from_now
    extension_factory = OpenSSL::X509::ExtensionFactory.new
    extension_factory.subject_certificate = certificate
    extension_factory.issuer_certificate = certificate
    certificate.add_extension(extension_factory.create_extension("basicConstraints", "CA:FALSE", true))
    certificate.add_extension(extension_factory.create_extension("keyUsage", "digitalSignature", true))
    certificate.add_extension(extension_factory.create_extension("subjectKeyIdentifier", "hash"))
    certificate.sign(key, OpenSSL::Digest::SHA256.new)

    AdesServerSigningService::Credential.new(certificate: certificate, private_key: key)
  end

  def create_verified_ades_session
    session = create_ades_session
    session.create_signature_verification!(
      channel: "sms",
      state: "verified",
      destination: "+421901234567",
      destination_digest: Digest::SHA256.hexdigest("+421901234567"),
      code_digest: Digest::SHA256.hexdigest("000000"),
      provider_request_id: "req-1",
      last_request_ip: "127.0.0.1",
      last_user_agent: "Rails Test",
      verified_at: Time.current,
      sent_at: Time.current,
      expires_at: 10.minutes.from_now
    )
    session.ensure_signature_evidence_record!.tap do |record|
      record.update!(state: "verified")
      record.append_event!(type: "sms_requested", details: { channel: "sms" })
      record.append_event!(type: "sms_verified", details: { channel: "sms" })
    end
    session
  end

  def create_ades_session
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "ades-server-signing.pdf",
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

    signer_contract.sessions.create!(
      type: "AdesEvidenceSession",
      signing_started_at: Time.current,
      options: { "verification_channel" => "sms" }
    )
  end
end
