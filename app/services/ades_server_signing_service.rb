class AdesServerSigningService
  class Error < StandardError; end
  class VerificationRequiredError < Error; end
  class CredentialNotConfiguredError < Error; end
  class SigningFailedError < Error; end

  class Credential
    attr_reader :certificate, :private_key

    def initialize(certificate:, private_key:)
      @certificate = certificate
      @private_key = private_key
    end

    def encoded_certificate
      Base64.strict_encode64(certificate.to_der)
    end

    def certificate_pem
      certificate.to_pem
    end

    def certificate_fingerprint_sha256
      Digest::SHA256.hexdigest(certificate.to_der)
    end

    def sign_bytes(payload)
      private_key.sign(OpenSSL::Digest::SHA256.new, payload)
    end

    def sign_base64_data(data_to_sign)
      raw_data = Base64.strict_decode64(data_to_sign)
      Base64.strict_encode64(sign_bytes(raw_data))
    end

    def signer_name
      extract_dn_component(certificate.subject, "CN")
    end

    def issuer_name
      extract_dn_component(certificate.issuer, "CN")
    end

    private

    def extract_dn_component(name, key)
      Array(name.to_a).find { |entry| entry[0] == key }&.[](1).presence || name.to_s
    end
  end

  def initialize(avm_service: AutogramEnvironment.avm_service, clock: -> { Time.current }, credential_loader: nil)
    @avm_service = avm_service
    @clock = clock
    @credential_loader = credential_loader || method(:load_credential)
  end

  def sign!(session:, ip_address:, user_agent:, app_host: nil)
    raise VerificationRequiredError, I18n.t("contracts.sessions.ades_evidence.errors.not_verified") unless session.verification_verified?

    now = @clock.call
    evidence_record = session.ensure_signature_evidence_record!
    credential = @credential_loader.call

    evidence_record.update!(locked_at: now)
    evidence_record.append_event!(
      type: "server_signing_requested",
      details: {
        ip_address: ip_address,
        user_agent: user_agent,
        signed_by: credential.signer_name,
        issued_by: credential.issuer_name
      },
      occurred_at: now
    )

    data_to_sign_structure = @avm_service.request_data_to_sign(
      session.contract,
      signer_contract: session.signer_contract,
      signing_certificate: credential.encoded_certificate,
      signature_reference: evidence_record.public_reference,
      signature_instance: app_host
    )
    signed_data = credential.sign_base64_data(data_to_sign_structure.fetch(:data_to_sign))
    signed_document = @avm_service.build_signed_document(
      session.contract,
      signer_contract: session.signer_contract,
      data_to_sign_structure: data_to_sign_structure,
      signed_data: signed_data,
      signature_reference: evidence_record.public_reference,
      signature_instance: app_host
    )

    session.update!(error_message: nil)
    session.accept_signed_file(signed_document)

    evidence_record.reload
    evidence_record.update!(
      state: "signed",
      contract_content_version: session.contract.latest_content_version
    )
    evidence_record.append_event!(
      type: "server_signed",
      details: {
        ip_address: ip_address,
        user_agent: user_agent,
        signed_by: credential.signer_name,
        issued_by: credential.issuer_name,
        contract_content_version_id: evidence_record.contract_content_version_id
      },
      occurred_at: now
    )
    evidence_record.reload
    sealed_manifest = build_signed_manifest(evidence_record, session, credential, now, signed_document: signed_document, app_host: app_host)
    evidence_record.update!(
      signed_manifest: sealed_manifest,
      manifest_sha256: Digest::SHA256.hexdigest(sealed_manifest)
    )
    evidence_record.attach_sealed_evidence!(sealed_manifest)
    evidence_record.attach_private_evidence_package!(
      build_private_evidence_package(
        session,
        evidence_record,
        credential: credential,
        signed_document: signed_document,
        public_manifest: sealed_manifest,
        private_manifest: build_private_signed_manifest(
          evidence_record,
          session,
          credential,
          now,
          signed_document: signed_document,
          public_manifest: sealed_manifest,
          app_host: app_host
        )
      )
    )

    session
  rescue Error => e
    record_signing_failure(evidence_record, error: e, ip_address: ip_address, user_agent: user_agent, occurred_at: @clock.call)
    raise
  rescue StandardError => e
    record_signing_failure(evidence_record, error: e, ip_address: ip_address, user_agent: user_agent, occurred_at: @clock.call)
    raise SigningFailedError, I18n.t("contracts.sessions.ades_evidence.errors.signing_failed")
  end

  private

  def load_credential
    pkcs12_base64 = ENV["ADES_SIGNING_PKCS12_BASE64"].presence
    pkcs12_path = ENV["ADES_SIGNING_PKCS12_PATH"].presence
    pkcs12_password = ENV["ADES_SIGNING_PKCS12_PASSWORD"]

    if pkcs12_base64.present? || pkcs12_path.present?
      raw_pkcs12 = pkcs12_base64.present? ? Base64.strict_decode64(pkcs12_base64) : File.binread(pkcs12_path)
      pkcs12 = OpenSSL::PKCS12.new(raw_pkcs12, pkcs12_password)
      return Credential.new(certificate: pkcs12.certificate, private_key: pkcs12.key)
    end

    return build_fallback_test_credential if Rails.env.development? || Rails.env.test?

    raise CredentialNotConfiguredError, I18n.t("contracts.sessions.ades_evidence.errors.missing_signing_credential")
  rescue ArgumentError, OpenSSL::PKCS12::PKCS12Error, Errno::ENOENT
    raise CredentialNotConfiguredError, I18n.t("contracts.sessions.ades_evidence.errors.invalid_signing_credential")
  end

  def build_fallback_test_credential
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = SecureRandom.random_number(2**20)
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

    Credential.new(certificate: certificate, private_key: key)
  end

  def build_signed_manifest(evidence_record, session, credential, signed_at, signed_document:, app_host: nil)
    unsigned_manifest = {
      "reference" => evidence_record.public_reference,
      "signed_at" => signed_at.iso8601,
      "session_id" => session.id,
      "contract_uuid" => session.contract.uuid,
      "signer_contract_id" => session.signer_contract_id,
      "verification_channel" => session.verification_channel,
      "signed_by" => credential.signer_name,
      "issued_by" => credential.issuer_name,
      "contract_content_version_id" => session.contract.latest_content_version&.id,
      "signature" => {
        "format" => session.contract.signature_parameters.format,
        "level" => session.contract.signature_parameters.level,
        "embedded_reference" => evidence_record.public_reference,
        "instance_host" => app_host,
        "signing_certificate_sha256" => credential.certificate_fingerprint_sha256
      },
      "documents" => {
        "original_documents" => build_original_document_descriptors(session),
        "signed_document" => build_signed_document_descriptor(session, signed_document)
      },
      "evidence" => {
        "payload_sha256" => evidence_record.payload_sha256,
        "canonical_payload" => evidence_record.canonical_payload_for_sealing
      }
    }

    seal_payload(unsigned_manifest, credential)
  end

  def build_private_signed_manifest(evidence_record, session, credential, signed_at, signed_document:, public_manifest:, app_host: nil)
    verification = session.signature_verification

    unsigned_manifest = {
      "reference" => evidence_record.public_reference,
      "signed_at" => signed_at.iso8601,
      "session_id" => session.id,
      "contract_uuid" => session.contract.uuid,
      "signer_contract_id" => session.signer_contract_id,
      "verification_channel" => session.verification_channel,
      "signed_by" => credential.signer_name,
      "issued_by" => credential.issuer_name,
      "contract_content_version_id" => session.contract.latest_content_version&.id,
      "recipient" => {
        "uuid" => session.recipient&.uuid,
        "email" => session.recipient&.email,
        "mobile_phone" => verification&.destination || session.recipient_mobile_phone
      },
      "verification" => {
        "channel" => verification&.channel,
        "destination" => verification&.destination,
        "destination_digest" => verification&.destination_digest,
        "provider_request_id" => verification&.provider_request_id,
        "sent_at" => verification&.sent_at&.iso8601,
        "verified_at" => verification&.verified_at&.iso8601,
        "last_request_ip" => verification&.last_request_ip,
        "last_user_agent" => verification&.last_user_agent
      },
      "signature" => {
        "format" => session.contract.signature_parameters.format,
        "level" => session.contract.signature_parameters.level,
        "embedded_reference" => evidence_record.public_reference,
        "instance_host" => app_host,
        "signing_certificate_sha256" => credential.certificate_fingerprint_sha256
      },
      "documents" => {
        "original_documents" => build_original_document_descriptors(session),
        "signed_document" => build_signed_document_descriptor(session, signed_document)
      },
      "evidence" => {
        "payload_sha256" => evidence_record.payload_sha256,
        "canonical_payload" => evidence_record.canonical_payload_for_sealing,
        "public_manifest_sha256" => Digest::SHA256.hexdigest(public_manifest)
      }
    }

    seal_payload(unsigned_manifest, credential)
  end

  def build_private_evidence_package(session, evidence_record, credential:, signed_document:, public_manifest:, private_manifest:)
    evidence_txt = build_private_evidence_txt(private_manifest)
    sign_request_body = @avm_service.build_detached_sign_request_payload(
      filename: "signature-evidence-#{evidence_record.public_reference}.txt",
      content: evidence_txt,
      content_type: "text/plain",
      level: "XAdES_BASELINE_B",
      container: "ASiC_E",
      packaging: "DETACHED"
    )
    data_to_sign_structure = @avm_service.request_data_to_sign_from_request(
      sign_request_body: sign_request_body,
      signing_certificate: credential.encoded_certificate
    )
    signed_data = credential.sign_base64_data(data_to_sign_structure.fetch(:data_to_sign))
    Base64.strict_decode64(
      @avm_service.build_signed_document_from_request(
        sign_request_body: sign_request_body,
        data_to_sign_structure: data_to_sign_structure,
        signed_data: signed_data
      )
    )
  end

  def build_private_evidence_txt(private_manifest)
    manifest_data = JSON.parse(private_manifest)
    lines = [ "AGP signature evidence", "" ]

    append_private_evidence_txt_value(lines, nil, manifest_data)
    lines.join("\n") + "\n"
  end

  def append_private_evidence_txt_value(lines, key_path, value)
    case value
    when Hash
      value.keys.sort.each do |child_key|
        child_path = [ key_path, child_key ].compact.join(".")
        append_private_evidence_txt_value(lines, child_path, value.fetch(child_key))
      end
    when Array
      value.each_with_index do |entry, index|
        append_private_evidence_txt_value(lines, "#{key_path}[#{index}]", entry)
      end
    when nil
      lines << "#{key_path}:"
    else
      lines << "#{key_path}: #{value}"
    end
  end

  def seal_payload(unsigned_manifest, credential)
    canonical_unsigned_manifest = canonical_json(unsigned_manifest)
    signature = credential.sign_bytes(canonical_unsigned_manifest)

    canonical_json(
      unsigned_manifest.merge(
        "seal" => {
          "algorithm" => "RSASSA-PKCS1-v1_5-SHA256",
          "signed_json_sha256" => Digest::SHA256.hexdigest(canonical_unsigned_manifest),
          "signature" => Base64.strict_encode64(signature),
          "certificate" => {
            "pem" => credential.certificate_pem,
            "sha256" => credential.certificate_fingerprint_sha256
          }
        }
      )
    )
  end

  def record_signing_failure(evidence_record, error:, ip_address:, user_agent:, occurred_at:)
    return if evidence_record.blank?

    evidence_record.append_event!(
      type: "server_signing_failed",
      details: {
        error_class: error.class.name,
        error_message: error.message,
        ip_address: ip_address,
        user_agent: user_agent
      },
      occurred_at: occurred_at
    )
  rescue StandardError
    nil
  end

  def build_original_document_descriptors(session)
    session.contract.documents.map do |document|
      content = document.blob.download

      {
        "filename" => document.blob.filename.to_s,
        "content_type" => document.blob.content_type,
        "byte_size" => content.bytesize,
        "sha256" => Digest::SHA256.hexdigest(content)
      }
    end
  end

  def build_signed_document_descriptor(session, signed_document)
    content = Base64.strict_decode64(signed_document)

    {
      "filename" => session.generate_signed_filename,
      "content_type" => session.send(:inferred_signed_content_type),
      "byte_size" => content.bytesize,
      "sha256" => Digest::SHA256.hexdigest(content)
    }
  end

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
end
