require "test_helper"
require_relative "../../support/signing_flow_helper"

class Received::AutogramBatchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SigningFlowHelper

  IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148".freeze

  setup do
    @signer = confirmed_user("signer@example.com")
    @first_tenant = Tenant.create!(name: "Firma A", plan: :pro)
    @second_tenant = Tenant.create!(name: "Firma B", plan: :pro)
  end

  test "batch page hands every awaiting document to the Autogram batch" do
    first = create_bundle(@first_tenant, "Zmluva A", [ "prva.pdf" ])
    second = create_bundle(@second_tenant, "Zmluva B", [ "druha.pdf" ])
    sign_in @signer

    get received_autogram_batch_path

    assert_response :success
    items = JSON.parse(css_select("[data-controller='signers--autogram-batch']").sole["data-signers--autogram-batch-items-value"])
    assert_equal [ "prva.pdf", "druha.pdf" ], items.map { |item| item["contract_name"] }
    assert_equal [ "Zmluva A", "Zmluva B" ], items.map { |item| item["bundle_name"] }
    assert_equal [ "Firma A", "Firma B" ], items.map { |item| item["sender"] }
    [ first, second ].zip(items).each do |bundle, item|
      session = bundle.recipients.sole.signer_contracts.sole.sessions.pending.sole
      assert_instance_of AutogramSession, session
      assert_match %r{\A/contracts/#{bundle.contracts.sole.uuid}/sessions/#{session.id}/upload\?session_token=}, item["upload_path"]
    end
    assert_select "a[href=?]", received_bundles_path, text: I18n.t("received.autogram_batches.show.back")
  end

  test "received list offers signing everything at once" do
    create_bundle(@first_tenant, "Zmluva A", [ "prva.pdf", "druha.pdf" ])
    sign_in @signer

    get received_bundles_path

    assert_response :success
    assert_select "a[href=?]", received_autogram_batch_path, text: I18n.t("received.autogram_batches.offer.action", count: 2)
  end

  test "a single awaiting document is not offered as a batch" do
    create_bundle(@first_tenant, "Zmluva A", [ "prva.pdf" ])
    sign_in @signer

    get received_bundles_path
    assert_select "a[href=?]", received_autogram_batch_path, count: 0

    get received_autogram_batch_path
    assert_redirected_to received_bundles_path(state: "awaiting")
    assert_equal I18n.t("received.autogram_batches.show.unavailable"), flash[:alert]
  end

  test "phones are told that batch signing needs a computer" do
    create_bundle(@first_tenant, "Zmluva A", [ "prva.pdf", "druha.pdf" ])
    sign_in @signer

    get received_bundles_path, headers: { "User-Agent" => IPHONE }
    assert_select "a[href=?]", received_autogram_batch_path, count: 0
    assert_includes response.body, I18n.t("received.autogram_batches.offer.mobile_hint")

    get received_autogram_batch_path, headers: { "User-Agent" => IPHONE }
    assert_redirected_to received_bundles_path(state: "awaiting")
    assert_equal I18n.t("bundles.autogram_batch.desktop_only"), flash[:alert]
  end

  test "batch signing requires signing in" do
    get received_autogram_batch_path

    assert_redirected_to new_user_session_path
  end

  private

  def create_bundle(tenant, name, filenames)
    contracts = filenames.map do |filename|
      Contract.create!(
        tenant: tenant,
        documents: [ Document.new(blob: pdf_blob(filename)) ],
        allowed_methods: [ "qes" ],
        signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
      )
    end
    Bundle.create!(tenant: tenant, name: name, contracts: contracts).tap do |bundle|
      bundle.recipients.create!(email: @signer.email)
    end
  end
end
