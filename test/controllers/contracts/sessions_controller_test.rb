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
      width: 260,
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
end
