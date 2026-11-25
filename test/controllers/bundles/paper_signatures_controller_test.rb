require "test_helper"
require_relative "../../support/signing_flow_helper"

# Only members of the organization that sent the bundle review scans of documents signed on paper
# and download them; the scan is never reachable by a public link.
class Bundles::PaperSignaturesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SigningFlowHelper

  setup do
    @original_allowed_methods = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, %w[qes standalone_qes ades scan])

    @organization = Tenant.create!(name: "Firma ABC", plan: :pro)
    @owner = confirmed_user("owner@firma-abc.sk", tenant: @organization, role: :owner)
    @bundle = paper_bundle(@organization, "papier@example.com")
    @paper = submitted_paper_signature(@bundle)
  end

  teardown do
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, @original_allowed_methods)
  end

  test "a member of the organization opens the review and downloads the scan" do
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    sign_in_with_tenant member, @organization

    get bundle_paper_signature_path(@bundle, @paper)
    assert_response :success
    assert_equal member, request.env["warden"].user(:user)
    assert_select "h1", "Kontrola podpisu na papieri"

    get scan_bundle_paper_signature_path(@bundle, @paper, disposition: "inline")
    assert_response :success
    assert_equal @paper.scan.download.b, response.body.b
  end

  test "a member of another organization cannot open, approve, return or download the scan" do
    outsider_organization = Tenant.create!(name: "Iná firma", plan: :pro)
    outsider = confirmed_user("outsider@ina-firma.sk", tenant: outsider_organization, role: :owner)
    sign_in_with_tenant outsider, outsider_organization

    get bundle_paper_signature_path(@bundle, @paper)
    assert_response :not_found
    assert_equal outsider, request.env["warden"].user(:user)
    get scan_bundle_paper_signature_path(@bundle, @paper, disposition: "inline")
    assert_response :not_found
    assert_not_equal @paper.scan.download.b, response.body.b
    post approve_bundle_paper_signature_path(@bundle, @paper)
    assert_response :not_found
    post return_scan_bundle_paper_signature_path(@bundle, @paper), params: { return_reason: "Nie." }
    assert_response :not_found

    assert @paper.reload.submitted?
    assert_nil @paper.reviewed_by
  end

  test "a member working in another of their organizations is told to switch" do
    other_organization = Tenant.create!(name: "Iná firma", plan: :pro)
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    other_organization.memberships.create!(user: member, role: :owner)
    sign_in_with_tenant member, other_organization

    [
      -> { get bundle_paper_signature_path(@bundle, @paper) },
      -> { get scan_bundle_paper_signature_path(@bundle, @paper) },
      -> { post approve_bundle_paper_signature_path(@bundle, @paper) }
    ].each do |request_action|
      request_action.call
      assert_redirected_to dashboard_path
      assert_equal I18n.t("tenants.alerts.other_tenant_record", name: "Firma ABC"), flash[:alert]
      assert_equal member, request.env["warden"].user(:user)
    end
    assert @paper.reload.submitted?
  end

  test "the scan downloads only for members" do
    get scan_bundle_paper_signature_path(@bundle, @paper, disposition: "inline")
    assert_redirected_to new_user_session_path
    assert_nil request.env["warden"].user(:user)

    post approve_bundle_paper_signature_path(@bundle, @paper)
    assert_redirected_to new_user_session_path
    assert @paper.reload.submitted?
  end

  test "a paper signature is found only within its bundle" do
    other_bundle = paper_bundle(@organization, "iny@example.com")
    sign_in_with_tenant @owner, @organization

    get bundle_paper_signature_path(other_bundle, @paper)
    assert_response :not_found
    get scan_bundle_paper_signature_path(other_bundle, @paper)
    assert_response :not_found
    post approve_bundle_paper_signature_path(other_bundle, @paper)
    assert_response :not_found
    assert @paper.reload.submitted?
  end

  test "a scan the signer discarded is no longer served" do
    @paper.cancel!
    sign_in_with_tenant @owner, @organization

    get scan_bundle_paper_signature_path(@bundle, @paper)
    assert_response :not_found
    assert_equal @owner, request.env["warden"].user(:user)
  end

  private

  def paper_bundle(tenant, email)
    Bundle.create!(
      tenant: tenant,
      contracts_attributes: [ {
        allowed_methods: [ "qes", "scan" ],
        signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" },
        documents_attributes: [ { blob: pdf_blob("papier.pdf") } ]
      } ],
      recipients_attributes: [ { email: email } ]
    )
  end

  def submitted_paper_signature(bundle)
    paper = PaperSignature.open_for!(bundle.recipients.sole.recipient_signer.signer_contracts.sole)
    paper.add_pages!([ Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg") ])
    assert paper.submit!
    paper
  end
end
