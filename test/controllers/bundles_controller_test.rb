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

  private

  def create_bundle_with_contracts(author:, count:, signed: false)
    contracts = count.times.map do |index|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("%PDF-1.4 test content #{index}"),
        filename: "bundle-contract-#{index}.pdf",
        content_type: "application/pdf"
      )

      contract = Contract.create!(
        user: author,
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

    Bundle.create!(author: author, contracts: contracts)
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
