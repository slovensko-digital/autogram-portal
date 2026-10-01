require "test_helper"
require_relative "../support/signing_flow_helper"

# End-to-end signature requests started from the web: an organization uploads a
# document, requests signatures and recipients sign it through the real endpoints.
class SignatureRequestFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper
  include SigningFlowHelper

  setup do
    @organization = Tenant.create!(name: "Firma ABC", plan: :pro)
    @owner = confirmed_user("owner@firma-abc.sk", tenant: @organization, role: :owner)
  end

  test "external recipient without an account signs a single document from the invitation email" do
    bundle = request_signature_from_web(as: @owner, filename: "zmluva.pdf")
    recipient = add_recipient(bundle, "external@example.com")
    sign_out @owner

    mail = mails_to("external@example.com").sole
    get link_in(mail, %r{/bundles/#{bundle.uuid}/sign})
    assert_response :success
    assert_includes response.body, "Firma ABC"
    assert_select "a[href*='#{signature_apps_contract_path(bundle.contracts.sole)}']"

    parameters = sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert_equal [ "zmluva.pdf" ], parameters["documents"].map { |document| document["filename"] }
    assert_not parameters["multiple_documents"]
    assert bundle.reload.completed?
    assert recipient.reload.signed?
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
  end

  test "colleague from the same organization signs while signed in and sees the request on both sides" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: @owner, filename: "interna.pdf")
    recipient = add_recipient(bundle, colleague.email)
    assert_equal colleague, recipient.user
    sign_out @owner

    sign_in colleague
    get bundles_path
    assert_includes response.body, bundle_path(bundle)
    get received_bundles_path
    assert_includes response.body, sign_bundle_path(bundle, recipient: recipient.uuid)

    get sign_bundle_path(bundle)
    assert_response :success
    sign_with_autogram(bundle.contracts.sole)

    assert recipient.reload.signed?
    assert bundle.reload.completed?
    assert_equal [ recipient ], bundle.recipients.to_a, "a colleague signs as the recipient, not as an author proxy"
  end

  test "recipient from another organization signs in their own organization without access to the sender's data" do
    outsider = confirmed_user("outsider@inafirma.sk")
    bundle = request_signature_from_web(as: @owner, filename: "dodavatel.pdf")
    recipient = add_recipient(bundle, outsider.email)
    sign_out @owner

    sign_in outsider
    get received_bundles_path
    assert_includes response.body, sign_bundle_path(bundle, recipient: recipient.uuid)
    get bundles_path
    assert_not_includes response.body, bundle_path(bundle)
    get bundle_path(bundle)
    assert_response :not_found

    sign_with_autogram(bundle.contracts.sole)

    assert bundle.reload.completed?
    assert_not outsider.member_of?(@organization)
  end

  test "with several recipients the bundle waits for all of them and owners are told about each signature" do
    co_owner = confirmed_user("co-owner@firma-abc.sk", tenant: @organization, role: :owner)
    bundle = request_signature_from_web(as: @owner, filename: "spolocna.pdf")
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner
    contract = bundle.contracts.sole

    sign_with_autogram(contract, recipient: first)

    assert first.reload.signed?
    assert second.reload.pending?
    assert_not bundle.reload.completed?
    [ @owner, co_owner ].each do |owner|
      assert_equal 1, mails_to(owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_contract_signed.subject") }
    end

    sign_with_autogram(contract, recipient: second)

    assert bundle.reload.completed?
    [ @owner, co_owner ].each do |owner|
      assert_equal 1, mails_to(owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
    end
  end

  test "with the any rule the first signature completes the bundle and releases the other recipients" do
    bundle = request_signature_from_web(as: @owner, filename: "jeden-staci.pdf")
    patch bundle_path(bundle), params: { bundle: { signing_rule: "any" } }
    assert_redirected_to bundle_path(bundle)
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner

    sign_with_autogram(bundle.contracts.sole, recipient: first)

    assert bundle.reload.completed?
    assert second.reload.superseded?
    assert_equal 1, mails_to(second.email).count { |m| m.subject == I18n.t("notification_mailer.signature_no_longer_required.subject") }

    get sign_bundle_path(bundle, recipient: second.uuid)
    assert_response :success
    contract = bundle.contracts.sole
    assert_select "a[href*='#{autogram_contract_sessions_path(contract)}']", count: 0
    assert_select "a[href*='#{signature_apps_contract_path(contract)}']", count: 0
  end

  test "released recipient can no longer sign, not even with a signing already in progress" do
    bundle = request_signature_from_web(as: @owner, filename: "jeden-staci.pdf")
    patch bundle_path(bundle), params: { bundle: { signing_rule: "any" } }
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner
    contract = bundle.contracts.sole

    in_progress = open_autogram_session(contract, recipient: second)
    sign_with_autogram(contract, recipient: first)
    assert second.reload.superseded?
    assert second.sessions.sole.canceled?, "the released recipient's pending signing is cancelled"

    upload_signed_file(contract, in_progress[:upload])
    assert_response :bad_request
    assert_equal I18n.t("bundles.sign.signature_no_longer_required"), response.parsed_body["error"]
    assert_equal 1, contract.reload.content_versions.count

    [
      autogram_contract_sessions_path(contract, recipient: second.uuid),
      ades_contract_sessions_path(contract, recipient: second.uuid),
      sign_contract_path(contract, recipient: second.uuid),
      signature_apps_contract_path(contract, recipient: second.uuid)
    ].each do |path|
      get path
      assert_redirected_to sign_bundle_path(bundle, recipient: second.uuid), "#{path} still lets a released recipient sign"
      assert_equal I18n.t("bundles.sign.signature_no_longer_required"), flash[:notice]
    end
    assert_equal 1, second.sessions.count
  end

  test "owner signs their own request too and is not notified about their own signature" do
    co_owner = confirmed_user("co-owner@firma-abc.sk", tenant: @organization, role: :owner)
    bundle = request_signature_from_web(as: @owner, filename: "obojstranna.pdf")
    recipient = add_recipient(bundle, "partner@example.com")

    get sign_bundle_path(bundle)
    assert_response :success
    sign_with_autogram(bundle.contracts.sole)

    author_proxy = bundle.recipients.author_proxies.sole
    assert_equal @owner, author_proxy.user
    assert_not bundle.reload.completed?, "the author's signature does not replace the recipient's"
    assert_empty mails_to(@owner.email).select { |m| m.subject == I18n.t("notification_mailer.bundle_contract_signed.subject") }
    assert_equal 1, mails_to(co_owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_contract_signed.subject") }
    sign_out @owner

    sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert bundle.reload.completed?
  end

  test "member signs a standalone document of the organization and the owner is notified" do
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    sign_in member
    post contracts_path, params: { document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 vlastny"), "application/pdf", original_filename: "vlastny.pdf") } }
    contract = Contract.order(:id).last
    assert_equal @organization, contract.tenant

    patch contract_path(contract), params: {
      next_step: "sign",
      contract: { allowed_methods: [ "qes" ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" } }
    }
    assert_redirected_to sign_contract_path(contract)
    sign_with_autogram(contract)

    assert contract.reload.signed_document_attached?
    assert_nil contract.bundle
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.contract_signed.subject") }
    assert_empty mails_to(member.email)
  end

  private

  # Uploads a PDF, asks for signatures and returns the bundle the web creates.
  def request_signature_from_web(as:, filename:)
    sign_in as
    post contracts_path, params: { document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 #{filename}"), "application/pdf", original_filename: filename) } }
    contract = Contract.order(:id).last
    assert_redirected_to contract_path(contract)
    assert_equal current_tenant_of(as), contract.tenant

    patch contract_path(contract), params: {
      next_step: "request_signature",
      contract: { allowed_methods: [ "qes" ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" } }
    }
    bundle = contract.reload.bundle
    assert_redirected_to bundle_path(bundle)
    assert_equal contract.tenant, bundle.tenant
    bundle
  end

  def add_recipient(bundle, email)
    post bundle_recipients_path(bundle), params: { recipient: { email: email } }, as: :turbo_stream
    assert_response :success
    recipient = bundle.recipients.active.find_by!(email: email)

    post notify_bundle_recipient_path(bundle, recipient), as: :turbo_stream
    assert_response :success
    assert recipient.reload.notified?
    recipient
  end

  def current_tenant_of(user)
    Tenant.find(session[:current_tenant_id]).tap { |tenant| assert user.member_of?(tenant) }
  end
end
