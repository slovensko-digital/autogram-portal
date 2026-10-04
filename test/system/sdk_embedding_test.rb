require "application_system_test_case"
require_relative "../support/sdk_embed_helper"

# Integrators open bundles and contracts on their own pages with the JavaScript SDK
# (/sdk.js, see public/sdk-example.html). These tests embed the portal the same way,
# cross-site unless stated otherwise, and check what the signer sees in the iframe
# and what the integrator page receives.
class SdkEmbeddingTest < ApplicationSystemTestCase
  include SdkEmbedHelper

  # Stand-ins for the SMS gateway and the server-side AdES signer.
  class FakeSmsProvider
    attr_reader :last_code

    def deliver_code(phone_number:, code:, locale: I18n.default_locale, context: {})
      @last_code = code
      "fake-sms-#{SecureRandom.hex(4)}"
    end
  end

  class FakeAdesSigningService
    def sign!(session:, ip_address:, user_agent:, app_host: nil)
      session.ensure_signature_evidence_record!.update!(state: "signed")
      session.signed!
    end
  end

  setup do
    @organization = Tenant.create!(name: "Firma ABC", plan: :pro)
  end

  test "bundle embedded in the integrator's container shows the signing page without portal navigation" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ], note: "Prosíme o podpis do piatku.")
    recipient = bundle.recipients.sole

    iframe = embed_with_sdk :initBundleIframe, bundle.uuid, parentElement: "#agp-container", recipientId: recipient.uuid, height: "600px"

    assert_selector "#agp-container > iframe[data-agp-session='#{bundle.uuid}']"
    assert_equal "600px", iframe.style("height")["height"]
    within_portal_frame do
      assert_text "Prosíme o podpis do piatku."
      assert_text "zmluva.pdf"
      assert_selector "a[target='_blank']", text: I18n.t("actions.view")
      assert_text I18n.t("bundles.sign.awaiting_recipients")
      assert_text "signer@example.com"
      assert_text I18n.t("bundles.sign.electronic_setup_title")
      assert_link I18n.t("bundles.sign.electronic_setup_action")

      assert_no_text "Autogram Portal"
      assert_no_text I18n.t("footer.support")
      assert_no_button I18n.t("bundles.sign.decline")
      assert_no_text I18n.t("bundles.sender.sender")
      wait_for_signature_validation
      assert_no_text I18n.t("shared.signature_validation.no_signatures_title")
    end
  end

  test "document that already has signatures shows them in the iframe" do
    contract = qes_contract("predpodpisana.pdf").merge(documents_attributes: [ { blob: presigned_blob("predpodpisana.pdf") } ])
    bundle = create_bundle(contracts: [ contract ], recipients: [ { email: "signer@example.com" } ])

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid

    within_portal_frame do
      assert_text I18n.t("shared.signature_validation.signatures_found_title")
      assert_text "E2E Signer"
    end
  end

  test "no_preview shows only the documents to sign" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ], note: "Prosíme o podpis do piatku.")

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, previewLevel: "no_preview"

    within_portal_frame do
      assert_text "zmluva.pdf"
      assert_text I18n.t("bundles.sign.electronic_setup_title")

      assert_no_text I18n.t("bundles.sender.sender")
      assert_no_text "Prosíme o podpis do piatku."
      assert_no_link I18n.t("actions.view")
      assert_no_text I18n.t("bundles.sign.awaiting_recipients")
      assert_no_text "signer@example.com"
    end
  end

  test "no_onboarding offers the signing apps right away" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, previewLevel: "no_onboarding"

    within_portal_frame do
      assert_text "zmluva.pdf"
      assert_text I18n.t("contracts.signature_apps.title")
      assert_field I18n.t("contracts.signature_apps.autogram_desktop_label"), checked: true, visible: :all
      assert_text I18n.t("contracts.signature_apps.eidentita_label")
      assert_button I18n.t("contracts.signature_apps.continue_to_sign")

      assert_no_text I18n.t("bundles.sign.electronic_setup_title")
      assert_no_text I18n.t("bundles.sender.sender")
    end
  end

  test "signing apps that cannot create the requested signature level are not offered" do
    contract = qes_contract("zmluva.pdf").merge(signature_parameters_attributes: { level: "BASELINE_T", format: "PAdES" })
    bundle = create_bundle(contracts: [ contract ], recipients: [ { email: "signer@example.com" } ])

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, previewLevel: "no_onboarding"

    within_portal_frame do
      assert_text I18n.t("contracts.signature_apps.autogram_desktop_label")
      assert_no_text I18n.t("contracts.signature_apps.podpisuj_label")
      assert_no_text I18n.t("contracts.signature_apps.unavailable_reasons.unsupported_signature_level")
    end
  end

  test "default embedding walks the signer through onboarding inside the iframe" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid

    within_portal_frame do
      wait_for_signature_validation
      click_on I18n.t("bundles.sign.electronic_setup_action")

      assert_text I18n.t("contracts.onboarding.qscd_check.title")
      choose I18n.t("qscd.title.eid_2024"), allow_label_click: true
      click_on I18n.t("contracts.onboarding.qscd_check.continue")

      assert_text I18n.t("contracts.onboarding.pin_check.title")
      click_on I18n.t("contracts.onboarding.pin_check.continue")

      assert_text I18n.t("contracts.onboarding.certificate_check.title")
      click_on I18n.t("contracts.onboarding.certificate_check.continue")

      assert_text I18n.t("contracts.signature_apps.title")
      assert_text I18n.t("qscd.title.eid_2024")
      assert_button I18n.t("contracts.signature_apps.continue_to_sign")
      assert_no_text "Autogram Portal"
    end
  end

  test "bundle with several documents offers signing them all at once" do
    bundle = create_bundle(
      contracts: [ qes_contract("prva.pdf"), qes_contract("druha.pdf"), qes_contract("tretia.pdf") ],
      recipients: [ { email: "signer@example.com" } ]
    )

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, previewLevel: "no_preview"

    within_portal_frame do
      assert_link I18n.t("bundles.sign.batch_sign_action")
      assert_text I18n.t("bundles.sign.individual_signing_section_title")
      assert_text I18n.t("bundles.sign.contract_number", current: 1, total: 3)
      assert_text I18n.t("bundles.sign.contract_number", current: 3, total: 3)
      %w[prva.pdf druha.pdf tretia.pdf].each { |filename| assert_text filename }
    end
  end

  test "locale option switches the iframe language" do
    bundle = create_bundle(contracts: [ qes_contract("contract.pdf") ], recipients: [ { email: "signer@example.com" } ])

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, locale: "en"

    within_portal_frame do
      assert_text I18n.t("bundles.sign.awaiting_recipients", locale: :en)
      assert_text I18n.t("bundles.sign.electronic_setup_title", locale: :en)
      assert_no_text I18n.t("bundles.sign.electronic_setup_title", locale: :sk)
    end
  end

  test "recipient who already signed sees the document as completed without a download" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    recipient = bundle.recipients.sole
    sign_outside_the_portal_frame(bundle.contracts.sole, recipient)

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid

    within_portal_frame do
      assert_text I18n.t("bundles.status.completed")
      assert_text I18n.t("contracts.sign.already_signed.title")
      assert_no_link I18n.t("actions.download_contract")
      assert_no_text I18n.t("bundles.sign.electronic_setup_title")
    end
  end

  test "recipient who declined sees the decline notice instead of signing options" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    recipient = bundle.recipients.sole
    recipient.signer_contracts.update_all(declined_at: Time.current)

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid

    within_portal_frame do
      assert_text I18n.t("bundles.sign.declined_info_title")
      assert_button I18n.t("actions.sign")
      assert_no_text I18n.t("bundles.sign.electronic_setup_title")
    end
  end

  test "withdrawn recipient sees that the request was withdrawn" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    recipient = bundle.recipients.sole
    recipient.withdraw!

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid

    within_portal_frame do
      assert_text I18n.t("bundles.sign.withdrawn_info_title")
      assert_no_text "zmluva.pdf"
      assert_no_text "Autogram Portal"
    end
  end

  test "contract allowing several signing methods lets the signer choose" do
    bundle = create_bundle(
      contracts: [ qes_contract("zmluva.pdf").merge(allowed_methods: %w[qes ades]) ],
      recipients: [ { email: "signer@example.com", mobile_phone: "+421900123456" } ]
    )

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid

    within_portal_frame do
      assert_text I18n.t("contracts.signing_method_choice.title")
      assert_text I18n.t("contracts.signing_method_choice.electronic_label")
      assert_text I18n.t("contracts.signing_method_choice.ades_label")
      assert_button I18n.t("contracts.signing_method_choice.continue")
    end
  end

  test "publicly visible bundle opens without a recipient" do
    bundle = create_bundle(contracts: [ qes_contract("verejna.pdf") ], publicly_visible: true)

    embed_with_sdk :initBundleIframe, bundle.uuid

    within_portal_frame do
      assert_text "verejna.pdf"
      assert_text I18n.t("bundles.sign.electronic_setup_title")
      assert_no_text I18n.t("bundles.sign.awaiting_recipients")
    end
  end

  test "standalone contract embedded with the contract API shows the preview and signing choice" do
    contract = Contract.create!(qes_contract("samostatna.pdf"))

    embed_with_sdk :initContractIframe, contract.uuid, parentElement: "#agp-container"

    within_portal_frame do
      assert_text "samostatna.pdf"
      assert_text I18n.t("contracts.visualization_with_toggle.show_document")
      assert_text I18n.t("contracts.signing_method_choice.electronic_label")
      assert_no_text "Autogram Portal"

      wait_for_signature_validation
      assert_no_text I18n.t("shared.signature_validation.no_signatures_title")
      click_on I18n.t("contracts.signing_method_choice.continue")

      assert_text I18n.t("contracts.onboarding.qscd_check.title")
      assert_no_text "Autogram Portal"
    end
  end

  test "standalone contract that already has signatures shows them in the iframe" do
    contract = Contract.create!(qes_contract("predpodpisana.pdf").merge(documents_attributes: [ { blob: presigned_blob("predpodpisana.pdf") } ]))

    embed_with_sdk :initContractIframe, contract.uuid

    within_portal_frame do
      assert_text I18n.t("shared.signature_validation.signatures_found_title")
      assert_text "E2E Signer"
    end
  end

  test "initIframe opens a contract without the preview when asked to" do
    contract = Contract.create!(qes_contract("samostatna.pdf"))

    iframe = embed_with_sdk :initIframe, contract.uuid, previewLevel: "no_preview"

    assert_includes iframe[:src], "/contracts/#{contract.uuid}/sign?iframe=no_preview"
    within_portal_frame do
      assert_text I18n.t("contracts.signing_method_choice.title")
      assert_no_text I18n.t("contracts.visualization_with_toggle.show_document")
    end
  end

  test "popup overlays the integrator page and closes with the close button, Escape and a click outside" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    popup_options = { mode: "popup", popupTitle: "Podpis zmluvy", popupWidth: 600, popupHeight: 500, recipientId: bundle.recipients.sole.uuid }

    {
      "close button" => -> { find("[data-agp-popup] button", text: "×").click },
      "Escape" => -> { find("body").send_keys(:escape) },
      "click outside" => -> { page.driver.browser.action.move_to_location(10, 10).click.perform }
    }.each do |way, close_popup|
      embed_with_sdk :initBundleIframe, bundle.uuid, **popup_options

      within("[data-agp-popup='#{bundle.uuid}']") { assert_text "Podpis zmluvy" }
      within_portal_frame { assert_text "zmluva.pdf" }

      close_popup.call
      assert_no_selector "[data-agp-popup]", wait: 2
      assert_selector "#agp-close-count", text: "1", exact_text: true, wait: 2
    rescue Minitest::Assertion => e
      raise e.exception("closing with #{way}: #{e.message}")
    end
  end

  test "popup closed earlier is not closed again by Escape in the next popup" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    popup_options = { mode: "popup", recipientId: bundle.recipients.sole.uuid }

    visit_integrator_page
    call_sdk :initBundleIframe, bundle.uuid, **popup_options
    find("[data-agp-popup] button", text: "×").click
    call_sdk :initBundleIframe, bundle.uuid, **popup_options
    find("body").send_keys(:escape)

    assert_no_selector "[data-agp-popup]"
    assert_selector "#agp-close-count", text: "2", exact_text: true
  end

  test "Escape after destroyAll does not close the destroyed popup again" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])

    embed_with_sdk :initBundleIframe, bundle.uuid, mode: "popup", recipientId: bundle.recipients.sole.uuid
    page.execute_script("window.agp.destroyAll()")
    assert_no_selector "[data-agp-popup]"
    find("body").send_keys(:escape)

    assert_selector "#agp-close-count", text: "0", exact_text: true
  end

  test "each embedded iframe passes on only its own messages" do
    first = create_bundle(contracts: [ qes_contract("prva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    second = create_bundle(contracts: [ qes_contract("druha.pdf") ], recipients: [ { email: "signer@example.com" } ])
    install_fake_autogram_app

    visit_integrator_page
    call_sdk :initBundleIframe, first.uuid, parentElement: "#agp-container", recipientId: first.recipients.sole.uuid, previewLevel: "no_onboarding"
    call_sdk :initBundleIframe, second.uuid, recipientId: second.recipients.sole.uuid, previewLevel: "no_onboarding"
    within_portal_frame(second.uuid) { click_on I18n.t("contracts.signature_apps.continue_to_sign") }

    assert_equal second.uuid, assert_portal_message("document-signed", to: second.uuid)["bundle_id"]
    assert_no_selector "#agp-messages li[data-instance='#{first.uuid}']"
  end

  test "recipient signs a document with Autogram inside the iframe" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    recipient = bundle.recipients.sole
    install_fake_autogram_app

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid, previewLevel: "no_onboarding"
    within_portal_frame do
      click_on I18n.t("contracts.signature_apps.continue_to_sign")

      assert_text I18n.t("contracts.sign.already_signed.title")
      assert_text I18n.t("bundles.status.completed")
    end

    assert recipient.reload.signed?
    assert bundle.reload.completed?
  end

  test "integrator is told when the recipient signs the last document in the iframe" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    install_fake_autogram_app

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, previewLevel: "no_onboarding"
    within_portal_frame { click_on I18n.t("contracts.signature_apps.continue_to_sign") }

    message = assert_portal_message("document-signed")
    assert_equal bundle.contracts.sole.uuid, message["contract_id"]
    assert_equal bundle.uuid, message["bundle_id"]
    assert message["bundle_completed"]
    assert message["close_iframe"]
  end

  test "integrator learns how many documents are left after the recipient signs one of several" do
    bundle = create_bundle(contracts: [ qes_contract("prva.pdf"), qes_contract("druha.pdf") ], recipients: [ { email: "signer@example.com" } ])
    recipient = bundle.recipients.sole
    first_contract = bundle.contracts.order(:updated_at).first
    install_fake_autogram_app

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid, previewLevel: "no_onboarding"
    within_portal_frame do
      within("turbo-frame#signature_apps_#{first_contract.uuid}") do
        click_on I18n.t("contracts.signature_apps.continue_to_sign")
      end
    end

    message = assert_portal_message("document-signed")
    assert_equal first_contract.uuid, message["contract_id"]
    assert_equal 2, message["total_contracts_count"]
    assert_equal 1, message["remaining_contracts_count"]
    assert_not message["bundle_completed"]
    assert_not message["close_iframe"]
    assert recipient.reload.pending?
  end

  test "integrator is told when the signed file is rejected" do
    bundle = create_bundle(contracts: [ qes_contract("zmluva.pdf") ], recipients: [ { email: "signer@example.com" } ])
    install_fake_autogram_app(signed: false)

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: bundle.recipients.sole.uuid, previewLevel: "no_onboarding"
    within_portal_frame do
      click_on I18n.t("contracts.signature_apps.continue_to_sign")

      assert_text I18n.t("contracts.sessions.error.title")
    end

    message = assert_portal_message("sign-error")
    assert_equal bundle.contracts.sole.uuid, message["contract_id"]
    assert_equal bundle.uuid, message["bundle_id"]
    assert_equal I18n.t("session.errors.no_signatures"), message["error_message"]
    assert_not bundle.reload.completed?
  end

  test "batch signing in the iframe signs every document and tells the integrator to close the iframe" do
    bundle = create_bundle(contracts: [ qes_contract("prva.pdf"), qes_contract("druha.pdf") ], recipients: [ { email: "signer@example.com" } ])
    recipient = bundle.recipients.sole
    install_fake_autogram_app

    embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid
    within_portal_frame do
      click_on I18n.t("bundles.sign.batch_sign_action")

      assert_text I18n.t("bundles.autogram_batch.success_title")
    end

    message = assert_portal_message("document-signed")
    assert_equal bundle.uuid, message["bundle_id"]
    assert_equal 2, message["total_contracts_count"]
    assert_equal 0, message["remaining_contracts_count"]
    assert message["bundle_completed"]
    assert message["close_iframe"]
    assert recipient.reload.signed?
    assert bundle.contracts.all?(&:signed_document_attached?)
  end

  test "recipient signs with a verified AdES signature inside an iframe on the portal's own site" do
    bundle = create_bundle(
      contracts: [ { allowed_methods: [ "ades" ], documents_attributes: [ { blob: pdf_blob("zmluva.pdf") } ] } ],
      recipients: [ { email: "signer@example.com", mobile_phone: "+421900123456" } ]
    )
    recipient = bundle.recipients.sole

    with_fake_ades_services do |sms_provider|
      embed_with_sdk :initBundleIframe, bundle.uuid, same_site: true, recipientId: recipient.uuid
      within_portal_frame do
        sign_with_ades(sms_provider)

        assert_ades_signed
      end
    end

    assert_portal_message("document-signed")
    assert recipient.reload.signed?
  end

  test "recipient signs with a verified AdES signature inside a cross-site iframe" do
    bundle = create_bundle(
      contracts: [ { allowed_methods: [ "ades" ], documents_attributes: [ { blob: pdf_blob("zmluva.pdf") } ] } ],
      recipients: [ { email: "signer@example.com", mobile_phone: "+421900123456" } ]
    )
    recipient = bundle.recipients.sole

    with_fake_ades_services do |sms_provider|
      embed_with_sdk :initBundleIframe, bundle.uuid, recipientId: recipient.uuid
      within_portal_frame do
        sign_with_ades(sms_provider)

        assert_ades_signed
      end
    end

    assert_portal_message("document-signed")
    assert recipient.reload.signed?
  end

  private

  def create_bundle(contracts:, recipients: [], **attributes)
    Bundle.create!(tenant: @organization, contracts_attributes: contracts, recipients_attributes: recipients, **attributes)
  end

  def qes_contract(filename)
    {
      allowed_methods: [ "qes" ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" },
      documents_attributes: [ { blob: pdf_blob(filename) } ]
    }
  end

  # The lazily loaded validation result moves the buttons below it.
  def wait_for_signature_validation
    assert_selector "turbo-frame[id^='signature_validation_'][complete]"
  end

  # A document FakeAutogramService reports as already signed.
  def presigned_blob(filename)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("#{SigningFlowHelper::SIGNED_PREFIX}#{filename}"), filename: filename, content_type: "application/pdf")
  end

  def sign_outside_the_portal_frame(contract, recipient)
    session = recipient.signer_contracts.find_by!(contract: contract).sessions.create!(type: "AutogramSession", signing_started_at: Time.current)
    session.accept_signed_file(Base64.strict_encode64("#{SigningFlowHelper::SIGNED_PREFIX}#{contract.uuid}"))
  end

  def sign_with_ades(sms_provider)
    click_on I18n.t("contracts.signing_method_choice.continue")
    click_on I18n.t("contracts.sessions.ades_evidence.request_code_button")
    code_field = find_field(I18n.t("contracts.sessions.ades_evidence.verification_code_label"))
    code_field.fill_in with: sms_provider.last_code
    click_on I18n.t("contracts.sessions.ades_evidence.verify_code_button")
    click_on I18n.t("contracts.sessions.ades_evidence.complete_signing_button")
  end

  def assert_ades_signed
    assert_text I18n.t("contracts.sessions.signed.title")
    assert_text(/#{Regexp.escape(I18n.t("contracts.sessions.signed.evidence_reference_label"))}/i)
    assert_link I18n.t("contracts.sessions.signed.verify_reference_link")
  end

  def with_fake_ades_services
    sms_provider = FakeSmsProvider.new
    signing_service = FakeAdesSigningService.new
    environment_singleton = AutogramEnvironment.singleton_class
    original_sms_provider = AutogramEnvironment.method(:sms_provider)
    original_signing_service = AutogramEnvironment.method(:ades_signing_service)
    environment_singleton.define_method(:sms_provider) { sms_provider }
    environment_singleton.define_method(:ades_signing_service) { signing_service }

    yield sms_provider
  ensure
    environment_singleton.define_method(:sms_provider) { original_sms_provider.call }
    environment_singleton.define_method(:ades_signing_service) { original_signing_service.call }
  end
end
