require "test_helper"
require_relative "../support/signing_flow_helper"
require_relative "../support/plan_limits_helper"

# End-to-end signature requests started from the web: an organization uploads a
# document, requests signatures and recipients sign it through the real endpoints.
class SignatureRequestFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper
  include SigningFlowHelper
  include PlanLimitsHelper

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

  test "recipient signs documents from two organizations in one Autogram batch" do
    signer = confirmed_user("signer@example.com")
    other_organization = Tenant.create!(name: "Firma XYZ", plan: :pro)
    other_owner = confirmed_user("owner@firma-xyz.sk", tenant: other_organization, role: :owner)
    first = request_signature_from_web(as: @owner, filename: "zmluva-abc.pdf")
    add_recipient(first, signer.email)
    second = request_signature_from_web(as: other_owner, filename: "zmluva-xyz.pdf", tenant: other_organization)
    add_recipient(second, signer.email)
    sign_out other_owner

    sign_in signer
    get received_bundles_path
    assert_select "a[href=?]", received_autogram_batch_path, text: I18n.t("received.autogram_batches.offer.action", count: 2)

    get received_autogram_batch_path
    assert_response :success
    items = JSON.parse(css_select("[data-controller='signers--autogram-batch']").sole["data-signers--autogram-batch-items-value"])
    assert_equal [ "zmluva-abc.pdf", "zmluva-xyz.pdf" ], items.map { |item| item["contract_name"] }

    # What the batch controller does for each item after Autogram signs it.
    [ first, second ].zip(items).each do |bundle, item|
      get item["parameters_path"]
      assert_response :success
      upload_signed_file(bundle.contracts.sole, item["upload_path"])
      assert_response :success, -> { "upload failed: #{response.body}" }
    end

    assert first.reload.completed?
    assert second.reload.completed?
    get received_bundles_path
    assert_select "a[href=?]", received_autogram_batch_path, count: 0
  end

  test "colleague from the same organization signs while signed in and sees the request on both sides" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: @owner, filename: "interna.pdf")
    recipient = add_recipient(bundle, colleague.email)
    assert_equal colleague, recipient.user
    sign_out @owner

    sign_in_with_tenant colleague, @organization
    get bundles_path
    assert_select "a[href=?]", bundle_path(bundle), text: bundle.display_name
    get received_bundles_path
    assert_select "a[href=?]", sign_bundle_path(bundle, recipient: recipient.uuid), text: bundle.display_name

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
    assert_select "a[href=?]", sign_bundle_path(bundle, recipient: recipient.uuid), text: bundle.display_name
    get bundles_path
    assert_not_includes response.body, bundle_path(bundle)
    get bundle_path(bundle)
    assert_response :not_found

    sign_with_autogram(bundle.contracts.sole)

    assert bundle.reload.completed?
    assert_not outsider.member_of?(@organization)
  end

  test "with several recipients the bundle waits for all of them and its author is told about each signature" do
    co_owner = confirmed_user("co-owner@firma-abc.sk", tenant: @organization, role: :owner)
    bundle = request_signature_from_web(as: @owner, filename: "spolocna.pdf")
    assert_equal @owner, bundle.author
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner
    contract = bundle.contracts.sole

    sign_with_autogram(contract, recipient: first)

    assert first.reload.signed?
    assert second.reload.pending?
    assert_not bundle.reload.completed?
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_contract_signed.subject") }

    sign_with_autogram(contract, recipient: second)

    assert bundle.reload.completed?
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
    assert_empty mails_to(co_owner.email), "other owners are not told about bundles they did not send"
  end

  test "a member's bundle notifies the member, not the owners" do
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: member, filename: "clenska.pdf")
    recipient = add_recipient(bundle, "partner@example.com")
    sign_out member

    sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert bundle.reload.completed?
    assert_equal member, bundle.author
    assert_equal 1, mails_to(member.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
    assert_empty mails_to(@owner.email)
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

  test "owner signs their own request too and nobody is notified about it" do
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
    assert_empty mails_to(co_owner.email), "the author's own signature is not news for the other owners"
    sign_out @owner

    sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert bundle.reload.completed?
  end

  test "member uploads and signs a standalone document and nobody is notified" do
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    sign_in_with_tenant member, @organization
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
    assert_equal member, contract.author
    assert_empty mails_to(@owner.email)
    assert_empty mails_to(member.email)
  end

  test "documents sent to recipients count once towards the monthly limit and sending stops at it" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "1") do
      bundle = request_signature_from_web(as: @owner, filename: "prva.pdf")
      add_recipient(bundle, "first@example.com")
      add_recipient(bundle, "second@example.com")
      assert_equal 1, @organization.usage_of(:signature_requests), "the same document is counted once"

      second_bundle = request_signature_from_web(as: @owner, filename: "druha.pdf")
      recipient = add_recipient_without_notifying(second_bundle, "third@example.com")
      post notify_bundle_recipient_path(second_bundle, recipient), as: :turbo_stream

      assert_response :success
      assert_includes response.body, I18n.t("plan_limits.exceeded.signature_requests", used: 1, max: 1)
      assert recipient.reload.not_notified?
      assert_empty mails_to("third@example.com")
      assert_equal 1, @organization.usage_of(:signature_requests)
    end
  end

  test "a bundle shared by a link counts when a recipient signs and cannot be signed beyond the limit" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "1") do
      bundle = request_signature_from_web(as: @owner, filename: "zdielana.pdf")
      recipient = add_recipient_without_notifying(bundle, "linked@example.com")
      over_limit = request_signature_from_web(as: @owner, filename: "nad-limit.pdf")
      over_limit_recipient = add_recipient_without_notifying(over_limit, "other@example.com")
      sign_out @owner

      sign_with_autogram(bundle.contracts.sole, recipient: recipient)

      assert bundle.reload.completed?
      assert_equal [ "recipient_signature" ], @organization.usage_records.signature_request.pluck(:source)

      contract = over_limit.contracts.sole
      get sign_bundle_path(over_limit, recipient: over_limit_recipient.uuid)
      assert_response :forbidden
      assert_includes response.body, I18n.t("bundles.sign_limit_reached.title")

      get sign_contract_path(contract, recipient: over_limit_recipient.uuid)
      assert_response :forbidden

      get autogram_contract_sessions_path(contract, recipient: over_limit_recipient.uuid)
      assert_response :unprocessable_entity
      assert_equal 0, contract.sessions.count
      assert_equal 1, @organization.usage_of(:signature_requests)
    end
  end

  test "the organization signing its own bundle does not count it as sent" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "0") do
      bundle = request_signature_from_web(as: @owner, filename: "vlastna.pdf")

      get sign_bundle_path(bundle)
      assert_response :success
      sign_with_autogram(bundle.contracts.sole)

      assert bundle.recipients.author_proxies.sole.signed?
      assert_equal 0, @organization.usage_of(:signature_requests)
    end
  end

  test "uploading beyond the stored documents limit explains why" do
    with_plan_limits("PRO_MAX_STORED_DOCUMENTS" => "1") do
      sign_in_with_tenant @owner, @organization
      upload_pdf("prvy.pdf")
      assert_redirected_to contract_path(Contract.order(:id).last)

      assert_no_difference -> { Contract.count } do
        upload_pdf("druhy.pdf")
      end
      assert_response :unprocessable_entity
      assert_includes response.body, I18n.t("activerecord.errors.models.contract.attributes.base.stored_documents_limit", max: 1)
    end
  end

  test "an anonymous document stays anonymous when the organization has no room for it after sign-in" do
    with_plan_limits("PRO_MAX_STORED_DOCUMENTS" => "0") do
      upload_pdf("anonymny.pdf", agree_to_policies: true)
      contract = Contract.order(:id).last
      assert contract.anonymous?

      post authenticate_for_actions_contract_path(contract)
      sign_in_with_tenant @owner, @organization
      get contract_path(contract)

      assert_response :success
      assert contract.reload.anonymous?
      assert_includes response.body, I18n.t("activerecord.errors.models.contract.attributes.base.stored_documents_limit", max: 0)
    end
  end

  test "the sidebar links the current tenant to its settings and names a Basic tenant generically" do
    organization_link = "a[href='#{edit_user_registration_path(anchor: "organization")}']"

    sign_in_with_tenant(@owner, @organization)
    get dashboard_path
    assert_select organization_link, text: /Firma ABC\s*#{I18n.t("tenants.plans.pro")}/

    sign_out @owner
    sign_in_with_tenant(@owner, @owner.tenants.basic.sole)
    get dashboard_path
    assert_select organization_link, text: I18n.t("header.current_tenant.personal")
  end

  test "the organization sees its plan usage on the dashboard and in its settings" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "10", "PRO_MAX_STORED_DOCUMENTS" => nil, "PRO_STORAGE_GB" => nil, "PRO_MONTHLY_TIMESTAMPS" => nil) do
      bundle = request_signature_from_web(as: @owner, filename: "pocitana.pdf")
      add_recipient(bundle, "partner@example.com")
      other = Tenant.create!(name: "Iná firma", plan: :pro)
      other.usage_records.create!(kind: :signature_request, source: :notification)

      get dashboard_path
      assert_response :success
      assert_select "section[aria-labelledby=dashboard-usage-title]", text: /#{I18n.t("tenants.usage.title")}/ do
        assert_select "li", count: 2
        assert_select "li", text: /#{I18n.t("tenants.usage.limits.signature_requests")}\s*1 \/ 10/
        assert_select "li", text: /#{I18n.t("tenants.usage.limits.timestamps")}\s*0\z/
      end

      get edit_user_registration_path
      assert_response :success
      assert_includes response.body, I18n.t("tenants.usage.limits.stored_documents")
      assert_includes response.body, I18n.t("tenants.usage.unlimited_value", used: 1)
      assert_select "[role=progressbar][aria-valuenow='1'][aria-valuemax='10']"
    end
  end

  test "the dashboard lists bundles awaiting my signature until I sign them" do
    outsider = confirmed_user("partner@inafirma.sk")
    awaiting_bundle = request_signature_from_web(as: @owner, filename: "na-podpis.pdf")
    recipient = add_recipient(awaiting_bundle, outsider.email)
    foreign_bundle = request_signature_from_web(as: @owner, filename: "pre-ineho.pdf")
    add_recipient(foreign_bundle, "iny@example.com")
    sign_out @owner

    sign_in outsider
    get dashboard_path
    assert_response :success
    assert outsider.tenants.sole.basic?
    assert_select "#organization-overview-title", count: 0
    assert_select "section[aria-labelledby=awaiting-signature-title]" do
      assert_select "#awaiting-signature-title", text: I18n.t("dashboard.index.awaiting.title_with_count", count: 1)
      assert_select "li", count: 1
      assert_select "a[href=?]", sign_bundle_path(awaiting_bundle, recipient: recipient.uuid),
                    text: "#{I18n.t("actions.view")}: #{awaiting_bundle.display_name}"
      assert_select "a[href*=?]", foreign_bundle.uuid, count: 0
    end

    sign_with_autogram(awaiting_bundle.contracts.sole, recipient: recipient)
    assert recipient.reload.signed?

    get dashboard_path
    assert_select "section[aria-labelledby=awaiting-signature-title]" do
      assert_select "#awaiting-signature-title", text: I18n.t("dashboard.index.awaiting.title")
      assert_select "li", count: 0
      assert_select "span", text: I18n.t("dashboard.index.awaiting.empty")
    end
  end

  test "a PRO dashboard shows my signatures above the organization overview" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    organization_bundle = request_signature_from_web(as: @owner, filename: "organizacna.pdf")
    add_recipient(organization_bundle, "partner@example.com")
    awaiting_me_bundle = request_signature_from_web(as: @owner, filename: "osobna.pdf")
    recipient = add_recipient(awaiting_me_bundle, colleague.email)
    sign_out @owner

    sign_in_with_tenant colleague, @organization
    get dashboard_path
    assert_response :success

    assert_select "#organization-overview-title", text: I18n.t("dashboard.index.organization.title")
    assert_select "section[aria-labelledby=organization-overview-title] p strong", text: "Firma ABC"

    assert_select "section[aria-labelledby=awaiting-signature-title]" do
      assert_select "#awaiting-signature-title", text: I18n.t("dashboard.index.awaiting.title_with_count", count: 1)
      assert_select "a[href=?]", sign_bundle_path(awaiting_me_bundle, recipient: recipient.uuid)
      assert_select "a[href*=?]", organization_bundle.uuid, count: 0
    end

    awaiting_me_row = recent_bundle_row(awaiting_me_bundle)
    organization_row = recent_bundle_row(organization_bundle)
    assert_includes awaiting_me_row.text, I18n.t("bundles.bundle_list.kind_awaiting_me")
    assert_not_includes organization_row.text, I18n.t("bundles.bundle_list.kind_awaiting_me")
  end

  test "a Basic organization sees documents it signed for others only within the signed history" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60", "SIGNED_HISTORY_DAYS" => "60") do
      outsider = confirmed_user("outsider@inafirma.sk")
      old_bundle = request_signature_from_web(as: @owner, filename: "stara.pdf")
      old_recipient = add_recipient(old_bundle, outsider.email)
      awaiting_bundle = request_signature_from_web(as: @owner, filename: "cakajuca.pdf")
      awaiting_recipient = add_recipient(awaiting_bundle, outsider.email)
      sign_out @owner
      sign_with_autogram(old_bundle.contracts.sole, recipient: old_recipient)
      old_bundle.update_column(:created_at, 61.days.ago)
      awaiting_bundle.update_column(:created_at, 61.days.ago)

      sign_in outsider
      get received_bundles_path

      assert_not_includes response.body, sign_bundle_path(old_bundle, recipient: old_recipient.uuid)
      assert_includes response.body, sign_bundle_path(awaiting_bundle, recipient: awaiting_recipient.uuid)
    end
  end

  private

  def upload_pdf(filename, agree_to_policies: false)
    params = { document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 #{filename}"), "application/pdf", original_filename: filename) } }
    params[:contract] = { agree_to_policies: "1" } if agree_to_policies
    post contracts_path, params: params
  end

  def add_recipient_without_notifying(bundle, email)
    post bundle_recipients_path(bundle), params: { recipient: { email: email } }, as: :turbo_stream
    assert_response :success
    bundle.recipients.active.find_by!(email: email)
  end

  # Uploads a PDF, asks for signatures and returns the bundle the web creates.
  def request_signature_from_web(as:, filename:, tenant: @organization)
    sign_in_with_tenant as, tenant
    post contracts_path, params: { document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 #{filename}"), "application/pdf", original_filename: filename) } }
    contract = Contract.order(:id).last
    assert_redirected_to contract_path(contract)
    assert_equal tenant, contract.tenant

    patch contract_path(contract), params: {
      next_step: "request_signature",
      contract: { allowed_methods: [ "qes" ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" } }
    }
    bundle = contract.reload.bundle
    assert_redirected_to bundle_path(bundle)
    assert_equal contract.tenant, bundle.tenant
    bundle
  end

  def recent_bundle_row(bundle)
    link = css_select("section[aria-labelledby=recent-bundles-title] a[href='#{bundle_path(bundle)}']").first
    assert link, "#{bundle.display_name} is not among the recent bundles"
    link.ancestors("div.px-4").first
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
end
