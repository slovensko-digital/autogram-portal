require "test_helper"

class BundlesControllerTest < ActionController::TestCase
  setup do
    @author = users(:one)
    @author.update_column(:email, "owner@example.com")
    author = @author
    @controller.singleton_class.define_method(:current_user) { author }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "author bundle sign route offers autogram batch signing for multiple qes contracts" do
    bundle = create_bundle_with_contracts(author: @author, count: 2)

    get :sign, params: { id: bundle.uuid }

    assert_response :success
    author_proxy = bundle.recipients.active.author_proxies.find_by!(user: @author)

    assert_select "a[href='#{autogram_batch_bundle_path(bundle, recipient: author_proxy.uuid)}']"
    assert_equal 1, bundle.recipients.active.author_proxies.where(user: @author).count
  end

  test "bundle show renders overview with edit link and lazy frames" do
    bundle = create_bundle_with_contracts(author: @author, count: 2)
    bundle.update!(name: "Employment agreement", note: "Please sign by Friday.", publicly_visible: true)

    get :show, params: { id: bundle.uuid }

    assert_response :success
    assert_select "h1", text: "Employment agreement"
    assert_select "a[href=?]", edit_bundle_path(bundle)
    assert_select "a[href=?]", sign_bundle_path(bundle)
    assert_select "turbo-frame#bundle_recipients_#{bundle.uuid}[src=?]", bundle_recipients_path(bundle)
    bundle.contracts.each do |contract|
      assert_select "turbo-frame##{dom_id(contract)}[src=?]", show_bundle_contract_path(contract)
    end
    assert_select "p", text: /Please sign by Friday\./
    assert_select "input[readonly][value=?]", sign_bundle_url(bundle)
    assert_select "form[action=?]", bundle_path(bundle) do
      assert_select "input[name='_method'][value='delete']"
    end
  end

  test "management verification catches a missing authorization call" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)
    @controller.singleton_class.define_method(:set_bundle) do
      @bundle = Bundle.find_by!(uuid: params[:id])
    end

    assert_raises(Pundit::AuthorizationNotPerformedError) do
      get :show, params: { id: bundle.uuid }
    end
  end

  test "list verification catches an unscoped relation" do
    @controller.singleton_class.define_method(:policy_scope) do |scope|
      scope.where(tenant: current_tenant)
    end

    assert_raises(Pundit::PolicyScopingNotPerformedError) do
      get :index
    end
  end

  test "author can open the edit form" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)

    get :edit, params: { id: bundle.uuid }

    assert_response :success
    assert_select "form[action=?]", bundle_path(bundle) do
      assert_select "input[name='bundle[name]'][placeholder=?]", bundle.display_name
      assert_select "textarea[name='bundle[note]']"
      assert_select "input[type='radio'][name='bundle[signing_rule]']", count: 3
      assert_select "input[name='bundle[required_signatures]']"
      assert_select "input[type='checkbox'][name='bundle[publicly_visible]']"
      assert_select "input[type='checkbox'][name='bundle[author_notifications_enabled]']"
    end
  end

  test "author can update bundle settings" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)

    patch :update, params: {
      id: bundle.uuid,
      bundle: {
        name: "Employment agreement",
        note: "Please sign by Friday.",
        signing_rule: "any",
        publicly_visible: "1",
        author_notifications_enabled: "1"
      }
    }

    assert_redirected_to bundle_path(bundle)
    assert_equal I18n.t("bundles.update.success"), flash[:notice]

    bundle.reload
    assert_equal "Employment agreement", bundle.name
    assert_equal "Please sign by Friday.", bundle.note
    assert_equal "any", bundle.signing_rule
    assert bundle.publicly_visible?
    assert bundle.author_notifications_enabled?
  end

  test "author can clear the bundle name and disable settings" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)
    bundle.update!(name: "Employment agreement", publicly_visible: true, author_notifications_enabled: true)

    patch :update, params: {
      id: bundle.uuid,
      bundle: { name: "", publicly_visible: "0", author_notifications_enabled: "0" }
    }

    assert_redirected_to bundle_path(bundle)

    bundle.reload
    assert_nil bundle.name.presence
    assert_not bundle.publicly_visible?
    assert_not bundle.author_notifications_enabled?
  end

  test "invalid bundle settings re-render the edit form" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)

    patch :update, params: { id: bundle.uuid, bundle: { signing_rule: "threshold", required_signatures: 0 } }

    assert_response :unprocessable_entity
    assert_equal "all", bundle.reload.signing_rule
    assert_select "form[action=?]", bundle_path(bundle)
    assert_select "[role='alert'], .bg-red-50", minimum: 1
  end

  test "bundle show offers archive extension for signed contracts" do
    bundle = create_bundle_with_contracts(author: @author, count: 1, signed: true)
    contract = bundle.contracts.first
    autogram_service = fake_autogram_service_with_signatures(
      AutogramService::ValidationSignature.new(
        signatureLevel: "BASELINE_T",
        validationResult: "TOTAL_PASSED",
        valid: true,
        timestampInfo: {
          qualified: true,
          timestamps: []
        },
        signerName: "Autogram Test"
      )
    )
    original_autogram_service = AutogramEnvironment.method(:autogram_service)

    AutogramEnvironment.singleton_class.define_method(:autogram_service) { autogram_service }

    begin
      get :show, params: { id: bundle.uuid }

      frame_selector = "turbo-frame#contract_#{contract.id}[src='#{show_bundle_contract_path(contract)}'][loading='lazy']"
      assert_select frame_selector, count: 1

      contracts_controller = ContractsController.new
      author = @author
      contracts_controller.singleton_class.define_method(:current_user) { author }
      contracts_controller.singleton_class.define_method(:user_signed_in?) { true }
      @controller = contracts_controller

      get :show_bundle, params: { id: contract.uuid }
    ensure
      AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
    end

    assert_response :success
    signed_preview_src = rails_blob_path(contract.latest_source_content_version.file, disposition: "inline")
    assert_select "iframe[src='#{signed_preview_src}#toolbar=0&navpanes=0&scrollbar=0&view=FitH']", count: 0
    assert_includes response.body, "data-src=\"#{signed_preview_src}#toolbar=0&navpanes=0&scrollbar=0&view=FitH\""
    assert_select "form[action='#{extend_signatures_contract_path(contract)}']"
    assert_select "input[name='target_level'][value='LTA']", count: 1
    assert_select "input[name='target_level'][value='T']", count: 0
    assert_includes response.body, I18n.t("contracts.signature_extension.levels.lta.title")
  end

  test "bundle show offers signature field preparation link for eligible unsigned contract" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)
    contract = bundle.contracts.first
    original_autogram_service = AutogramEnvironment.method(:autogram_service)
    fake_service = fake_unsigned_pades_validation_service

    AutogramEnvironment.singleton_class.define_method(:autogram_service) { fake_service }

    begin
      contracts_controller = ContractsController.new
      author = @author
      contracts_controller.singleton_class.define_method(:current_user) { author }
      contracts_controller.singleton_class.define_method(:user_signed_in?) { true }
      @controller = contracts_controller

      get :show_bundle, params: { id: contract.uuid }
    ensure
      AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
    end

    assert_response :success
    assert_select "a[href='#{contract_signature_field_preparations_path(contract)}']"
  end

  test "bundle show replaces the prepare fields call to action once every recipient has a field" do
    bundle = create_bundle_with_contracts(author: @author, count: 1)
    contract = bundle.contracts.first
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 1,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )

    original_autogram_service = AutogramEnvironment.method(:autogram_service)
    fake_service = fake_unsigned_pades_validation_service

    AutogramEnvironment.singleton_class.define_method(:autogram_service) { fake_service }

    begin
      contracts_controller = ContractsController.new
      author = @author
      contracts_controller.singleton_class.define_method(:current_user) { author }
      contracts_controller.singleton_class.define_method(:user_signed_in?) { true }
      @controller = contracts_controller

      get :show_bundle, params: { id: contract.uuid }
    ensure
      AutogramEnvironment.singleton_class.define_method(:autogram_service) { original_autogram_service.call }
    end

    assert_response :success
    assert_select "a[href=?]", contract_signature_field_preparations_path(contract), text: I18n.t("contracts.show_bundle.edit_signature_fields")
    assert_select "a", text: I18n.t("documents.new.actions.prepare_signature_fields.title"), count: 0
  end

  test "bundle show offers private evidence download for signed contract with evidence package" do
    bundle = create_bundle_with_contracts(author: @author, count: 1, signed: true)
    contract = bundle.contracts.first
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en", mobile_phone: "+421901234567")
    signer_contract = recipient.recipient_signer.signer_contracts.find_by!(contract: contract)
    session = signer_contract.sessions.create!(
      type: "AdesEvidenceSession",
      signing_started_at: Time.current,
      status: :signed,
      options: { "verification_channel" => "sms" }
    )
    evidence_record = session.create_signature_evidence_record!(
      signer_contract: signer_contract,
      state: "signed",
      contract_content_version: contract.latest_content_version,
      canonical_payload: { "verification_channel" => "sms", "events" => [] }
    )
    evidence_record.attach_private_evidence_package!("signed-evidence-asice")

    contracts_controller = ContractsController.new
    author = @author
    contracts_controller.singleton_class.define_method(:current_user) { author }
    contracts_controller.singleton_class.define_method(:user_signed_in?) { true }
    @controller = contracts_controller

    get :show_bundle, params: { id: contract.uuid }

    assert_response :success
    assert_select "a[href='#{download_private_signature_evidence_verification_path(reference: evidence_record.public_reference)}']", count: 1
    assert_includes response.body, I18n.t("contracts.show_bundle.private_evidence_download_button")
  end

  test "received lists pending invitations from trusted portals" do
    @author.update_column(:email, "recipient@example.com")
    portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://partner.example/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    )
    invitation = FederationRequestInvitation.create!(
      portal_instance: portal_instance,
      origin_recipient_uuid: SecureRandom.uuid,
      origin_bundle_uuid: SecureRandom.uuid,
      recipient_email: @author.email,
      payload: {
        "authorName" => "Remote sender",
        "openUrl" => "https://origin.example/bundles/123/sign?recipient=abc",
        "contracts" => [ { "displayName" => "Remote Contract" } ],
        "note" => "Please sign remotely"
      }
    )

    get :received

    assert_response :success
    assert_includes response.body, I18n.t("bundles.received.external_invitation_title")
    assert_includes response.body, portal_instance.name
    assert_includes response.body, federation_requests_open_path(url: invitation.payload["openUrl"])
  end

  test "received signed filter lists signed invitations from trusted portals" do
    @author.update_column(:email, "recipient@example.com")
    portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://partner.example/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    )
    FederationRequestInvitation.create!(
      portal_instance: portal_instance,
      origin_recipient_uuid: SecureRandom.uuid,
      origin_bundle_uuid: SecureRandom.uuid,
      recipient_email: @author.email,
      status: "signed",
      withdrawn_at: Time.current,
      payload: {
        "authorName" => "Remote sender",
        "openUrl" => "https://origin.example/bundles/123/sign?recipient=abc",
        "contracts" => [ { "displayName" => "Remote Contract" } ]
      }
    )

    get :received, params: { state: "signed" }

    assert_response :success
    assert_includes response.body, I18n.t("bundles.received.external_invitation_title")
    assert_includes response.body, I18n.t("bundles.received.state_signed")
  end

  private

  def create_bundle_with_contracts(author:, count:, signed: false)
    contracts = count.times.map do |index|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("%PDF-1.4 test content #{index}"),
        filename: "bundle-contract-#{index}.pdf",
        content_type: "application/pdf"
      )

      contract = Contract.create!(
        allowed_methods: [ "qes" ],
        documents_attributes: [ { blob: blob } ],
        signature_parameters_attributes: {
          level: "BASELINE_B",
          format: "PAdES"
        }
      )

      if signed
        contract.add_signed_content_version!(
          content: "%PDF-1.4 signed content #{index}",
          filename: "bundle-contract-signed-#{index}.pdf",
          content_type: "application/pdf",
          origin: "uploaded_signed"
        )
      end

      contract
    end

    Bundle.create!(tenant: author.tenants.sole, contracts: contracts)
  end

  def fake_autogram_service_with_signatures(*signatures)
    Class.new do
      define_method(:initialize) do |validation_signatures|
        @validation_signatures = validation_signatures
      end

      define_method(:validate_signatures) do |_document|
        AutogramService::ValidationResult.new(
          hasSignatures: true,
          signatures: @validation_signatures
        )
      end
    end.new(signatures)
  end

  def fake_unsigned_pades_validation_service
    Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(
      AutogramService::ValidationResult.new(
        hasSignatures: false,
        signatures: [],
        documentInfo: { signatureForm: "PAdES" }
      )
    )
  end
end
