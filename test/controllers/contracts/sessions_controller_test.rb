require "test_helper"

class Contracts::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @contract, @session = create_contract_with_session
    @autogram_service = AutogramService.new
    Rails.application.config.action_controller.default_url_options = { host: "example.com" }
  end

  test "download is forbidden without token or authorized user" do
    get "/contracts/#{@contract.uuid}/sessions/#{@session.id}/download"

    assert_response :forbidden
  end

  test "upload is forbidden without token or authorized user" do
    post "/contracts/#{@contract.uuid}/sessions/#{@session.id}/upload", params: {
      signed_document: Base64.strict_encode64("forged")
    }

    assert_response :forbidden
  end

  test "download succeeds with valid session token" do
    token = SessionAccessToken.generate(contract: @contract, session: @session)

    get "/contracts/#{@contract.uuid}/sessions/#{@session.id}/download", params: {
      session_token: token
    }

    assert_response :success
  end

  test "download uses signer prepared qes visual stamp" do
    visual_stamp = @session.signer_contract.visual_stamps.create!(
      document: @contract.documents.first,
      purpose: :qes_preparation,
      page: 1,
      x: 40,
      y: 40,
      width: 256,
      height: 52,
      text: VisualStamp::DEFAULT_TEXT
    )
    visual_stamp.file.attach(
      io: StringIO.new("prepared qes pdf"),
      filename: "prepared.pdf",
      content_type: "application/pdf"
    )

    token = SessionAccessToken.generate(contract: @contract, session: @session)

    get "/contracts/#{@contract.uuid}/sessions/#{@session.id}/download", params: {
      session_token: token
    }

    assert_response :success
    assert_equal "prepared qes pdf", response.body
  end

  test "create stores iframe mode on autogram sessions" do
    contract = create_contract_without_session

    get "/contracts/#{contract.uuid}/sessions/autogram", params: { iframe: "true" }

    assert_response :success
    assert_equal "true", contract.sessions.order(:id).last.options["iframe"]
  end

  test "parameters include visible signature text payload for prepared signature fields" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed by first recipient",
      filename: "visual-test-signed-once.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)
    signer_contract.visual_stamps.create!(
      document: contract.documents.first,
      purpose: :signature_field_appearance,
      page: 2,
      x: 42,
      y: 64,
      width: 180,
      height: 64,
      text: "Prepared signer name"
    )
    session = signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current
    )

    get "/contracts/#{contract.uuid}/sessions/#{session.id}/parameters", params: {
      session_token: SessionAccessToken.generate(contract: contract, session: session)
    }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal false, payload.fetch("multiple_documents")

    visible_signature = payload.fetch("documents").first.fetch("visible_signature")
    assert_equal contract.signature_field_preparations.first.field_identifier, visible_signature.fetch("field_id")
    assert_equal VisualStamp.pades_visible_signature_text("Prepared signer name"), visible_signature.fetch("text")
    assert_not visible_signature.key?("image")
  end

  test "parameters omit visible signature text for graphic prepared signature fields" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed by first recipient",
      filename: "visual-test-signed-once.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)
    visual_stamp = signer_contract.visual_stamps.new(
      document: contract.documents.first,
      purpose: :signature_field_appearance,
      page: 2,
      x: 42,
      y: 64,
      width: 180,
      height: 64,
      text: nil
    )
    visual_stamp.image.attach(
      io: StringIO.new("fake-png-content"),
      filename: "signature.png",
      content_type: "image/png"
    )
    visual_stamp.save!
    session = signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current
    )

    get "/contracts/#{contract.uuid}/sessions/#{session.id}/parameters", params: {
      session_token: SessionAccessToken.generate(contract: contract, session: session)
    }

    assert_response :success

    payload = JSON.parse(response.body)
    visible_signature = payload.fetch("documents").first.fetch("visible_signature")
    assert_equal contract.signature_field_preparations.first.field_identifier, visible_signature.fetch("field_id")
    assert_not visible_signature.key?("text")
    assert_equal "signature.png", visible_signature.dig("image", "filename")
    assert_equal "image/png;base64", visible_signature.dig("image", "mime_type")
    assert_equal Base64.strict_encode64("fake-png-content"), visible_signature.dig("image", "content")
  end

  test "create stores avm identifiers together with iframe mode" do
    contract = create_contract_without_session
    started_at = Time.current.change(usec: 0)

    with_avm_service(Struct.new(:started_at) do
      def initiate_signing(_contract, signer_contract: nil)
        {
          document_identifier: "guid-123",
          encryption_key: "secret-key-456",
          signing_started_at: started_at
        }
      end
    end.new(started_at)) do
      without_avm_poll_job do
        get "/contracts/#{contract.uuid}/sessions/avm", params: { iframe: "true" }
      end

      assert_response :success

      session = contract.sessions.order(:id).last
      assert_instance_of AvmSession, session
      assert_equal "true", session.options["iframe"]
      assert_equal "guid-123", session.document_identifier
      assert_equal "secret-key-456", session.encryption_key
      assert_equal started_at.to_i, session.signing_started_at.to_i
    end
  end

  test "avm session creation renders inline error instead of raising when mobile signing init fails" do
    contract = create_contract_without_session

    with_avm_service(Struct.new(:message) do
      def initiate_signing(_contract, signer_contract: nil)
        { error: message }
      end
    end.new("AVM temporarily unavailable")) do
      get "/contracts/#{contract.uuid}/sessions/avm", params: { iframe: "true", embedded: true }

      assert_response :unprocessable_entity
      assert_select "turbo-frame##{"signature_apps_#{contract.uuid}"}"
      assert_includes response.body, "AVM temporarily unavailable"
    end
  end

  test "signed bundle session redirect preserves iframe mode" do
    contract, session = create_bundle_contract_with_session(options: { "iframe" => "true" })
    token = SessionAccessToken.generate(contract: contract, session: session)
    session.update_columns(status: Session.statuses[:signed], completed_at: Time.current)

    get "/contracts/#{contract.uuid}/sessions/#{session.id}", params: { session_token: token }

    assert_redirected_to sign_bundle_path(contract.bundle, iframe: "true")
  end

  test "show renders signed session when explicitly requested" do
    @session.update!(status: :signed, completed_at: Time.current)

    get "/contracts/#{@contract.uuid}/sessions/#{@session.id}", params: { show_completed: "true" }

    assert_response :success
    assert_includes response.body, I18n.t("contracts.sessions.signed.title")
    assert_select "a[href='#{contract_path(@contract)}'][data-turbo-frame='_top']"
  end

  test "upload succeeds for indeterminate autogram test certificate in test environment" do
    validation_result = AutogramService::ValidationResult.new(
      hasSignatures: true,
      signatures: [
        parsed_signature(
          validation_result: "INDETERMINATE",
          subject_dn: "CN=Autogram Test, OU=Autogram, O=Autogram, L=Bratislava, ST=Bratislava, C=SK"
        )
      ],
      documentInfo: { signed_objects_count: 1 }
    )

    with_autogram_service(fake_validation_service(validation_result)) do
      post "/contracts/#{@contract.uuid}/sessions/#{@session.id}/upload", params: {
        session_token: SessionAccessToken.generate(contract: @contract, session: @session),
        signed_document: Base64.strict_encode64("signed")
      }

      assert_response :success
      assert_equal({ "success" => true }, JSON.parse(response.body))
      assert @session.reload.signed?
    end
  end

  test "upload rejects indeterminate signature from unknown certificate" do
    validation_result = AutogramService::ValidationResult.new(
      hasSignatures: true,
      signatures: [
        parsed_signature(
          validation_result: "INDETERMINATE",
          subject_dn: "CN=Unknown Test, OU=Autogram, O=Autogram, L=Bratislava, ST=Bratislava, C=SK"
        )
      ],
      documentInfo: { signed_objects_count: 1 }
    )

    with_autogram_service(fake_validation_service(validation_result)) do
      post "/contracts/#{@contract.uuid}/sessions/#{@session.id}/upload", params: {
        session_token: SessionAccessToken.generate(contract: @contract, session: @session),
        signed_document: Base64.strict_encode64("signed")
      }

      assert_response :bad_request
      assert_equal "Signed document signatures are invalid", JSON.parse(response.body).fetch("error")
      assert @session.reload.failed?
    end
  end

  test "destroy is forbidden without authorized user" do
    session_id = @session.id

    delete "/contracts/#{@contract.uuid}/sessions/#{session_id}"

    assert_response :forbidden
    assert Session.exists?(session_id)
  end

  private

  def parsed_signature(validation_result:, subject_dn:)
    @autogram_service.send(
      :parse_signature_info,
      {
        "validationResult" => validation_result,
        "signingCertificate" => {
          "subjectDN" => subject_dn,
          "issuerDN" => subject_dn,
          "qualification" => "NA"
        },
        "timestamps" => []
      },
      {}
    )
  end

  def fake_validation_service(validation_result)
    Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(validation_result)
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

  def with_avm_service(fake_service)
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:alias_method, :__original_avm_service, :avm_service)
    environment_singleton.send(:define_method, :avm_service) { fake_service }

    yield
  ensure
    environment_singleton.send(:remove_method, :avm_service)
    environment_singleton.send(:alias_method, :avm_service, :__original_avm_service)
    environment_singleton.send(:remove_method, :__original_avm_service)
  end

  def without_avm_poll_job
    job_singleton = Avm::SigningPollJob.singleton_class
    job_singleton.send(:alias_method, :__original_perform_later, :perform_later)
    job_singleton.send(:define_method, :perform_later) { |_session| nil }

    yield
  ensure
    job_singleton.send(:remove_method, :perform_later)
    job_singleton.send(:alias_method, :perform_later, :__original_perform_later)
    job_singleton.send(:remove_method, :__original_perform_later)
  end

  def create_contract_with_session
    contract = create_contract_without_session

    signer = AnonymousSigner.create!
    signer_contract = signer.signer_contracts.create!(contract: contract)
    session = signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current
    )

    [ contract, session ]
  end

  def create_contract_without_session
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "session-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.new(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    contract.save!

    contract
  end

  def create_bundle_contract_with_session(options: nil)
    author = users(:one)
    contract = create_contract_without_session
    bundle = Bundle.create!(author: author, contracts: [ contract ], publicly_visible: true)

    signer = AnonymousSigner.create!
    signer_contract = signer.signer_contracts.create!(contract: contract)
    session = signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current,
      options: options
    )

    [ contract.reload, session ]
  end

  def create_bundle_contract_with_prepared_signature_field
    contract = create_contract_without_session
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")

    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 2,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )

    contract.add_prepared_signature_fields_content_version!(
      content: "%PDF-1.4 prepared source",
      filename: "visual-test-prepared-fields.pdf",
      content_type: "application/pdf"
    )

    [ contract.reload, recipient.reload ]
  end
end
