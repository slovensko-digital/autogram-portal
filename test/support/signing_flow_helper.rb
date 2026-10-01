# Helpers for end-to-end signing tests: they drive the real web endpoints and
# only replace the external Autogram validation with a fake that accepts any upload.
module SigningFlowHelper
  SIGNED_PREFIX = "signed:".freeze

  # Reports files uploaded by #sign_with_autogram as validly signed and everything else as unsigned.
  class FakeAutogramService
    def validate_signatures(document)
      content = document.content.to_s
      return AutogramService::ValidationResult.new(hasSignatures: false) unless content.start_with?(SIGNED_PREFIX)

      container = document.blob.filename.to_s.end_with?(".asice") ? "ASiC_E" : nil
      AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          AutogramService::ValidationSignature.new(
            signerName: "E2E Signer",
            signingTime: Time.current,
            signatureLevel: "BASELINE_B",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: { subject: "CN=E2E Signer", issuer: "CN=Issuer", qualification: "QESIG", notAfter: 2.years.from_now.iso8601 }
          )
        ],
        documentInfo: { signatureForm: container ? "XAdES" : "PAdES", containerType: container, signedObjectsCount: 1, unsignedObjectsCount: 0, signedObjects: [], unsignedObjects: [] }
      )
    end
  end

  def self.included(base)
    base.setup do
      @original_default_url_options = Rails.application.config.action_controller.default_url_options
      # The Autogram instructions on the signing page print the application host.
      Rails.application.config.action_controller.default_url_options = { host: "example.com" }
      ActionMailer::Base.deliveries.clear
      install_fake_autogram
    end

    base.teardown do
      # The option is unset (nil) by default, but controllers merge it into every URL.
      Rails.application.config.action_controller.default_url_options = @original_default_url_options || {}
      restore_autogram
    end
  end

  def install_fake_autogram
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:alias_method, :__original_autogram_service, :autogram_service)
    fake_service = FakeAutogramService.new
    environment_singleton.send(:define_method, :autogram_service) { fake_service }
  end

  def restore_autogram
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:remove_method, :autogram_service)
    environment_singleton.send(:alias_method, :autogram_service, :__original_autogram_service)
    environment_singleton.send(:remove_method, :__original_autogram_service)
  end

  # Opens an Autogram signing session the way the signing page does, checks the
  # parameters Autogram would receive and uploads a signed file.
  # Returns the parsed signing parameters.
  def sign_with_autogram(contract, recipient: nil)
    paths = open_autogram_session(contract, recipient: recipient)

    get paths[:parameters]
    assert_response :success
    parameters = response.parsed_body

    upload_signed_file(contract, paths[:upload])
    assert_response :success, -> { "upload failed: #{response.body}" }

    parameters
  end

  # Returns the parameters and upload paths the signing page hands over to Autogram.
  def open_autogram_session(contract, recipient: nil)
    get autogram_contract_sessions_path(contract, recipient: recipient&.uuid)
    assert_response :success

    parameters_path = response.body[/autogram-parameters-path-value="([^"]+)"/, 1]
    upload_path = response.body[/signed-document-path-value="([^"]+)"/, 1]
    assert parameters_path, "signing page does not expose the Autogram parameters path"
    assert upload_path, "signing page does not expose the upload path"

    { parameters: CGI.unescapeHTML(parameters_path), upload: CGI.unescapeHTML(upload_path) }
  end

  def upload_signed_file(contract, upload_path)
    post upload_path, params: { signed_document: Base64.strict_encode64("#{SIGNED_PREFIX}#{contract.uuid}") }
  end

  def pdf_blob(filename = "document.pdf")
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 #{filename}"), filename: filename, content_type: "application/pdf")
  end

  def confirmed_user(email, tenant: nil, role: :member)
    user = User.create!(email: email, confirmed_at: Time.current)
    tenant&.memberships&.create!(user: user, role: role)
    accept_current_policies!(user)
    user
  end

  # Signs +user+ in and picks +tenant+, as users with several tenants must.
  def sign_in_with_tenant(user, tenant)
    sign_in user
    post tenant_selection_path(tenant_id: tenant.id)
  end

  def accept_current_policies!(user)
    PolicyVersions.current.each do |policy_type, version|
      user.policy_consents.create!(policy_type: policy_type, policy_version: version, source: "email_signup", accepted_at: Time.current)
    end
  end

  def mails_to(email)
    ActionMailer::Base.deliveries.select { |mail| mail.to.include?(email) }
  end

  def link_in(mail, pattern)
    body = mail.html_part&.body&.decoded || mail.body.decoded
    href = body.scan(/href="([^"]+)"/).flatten.map { |link| CGI.unescapeHTML(link) }.find { |link| link.match?(pattern) }
    assert href, "no link matching #{pattern.inspect} in mail #{mail.subject.inspect}"
    URI(href).request_uri
  end
end
