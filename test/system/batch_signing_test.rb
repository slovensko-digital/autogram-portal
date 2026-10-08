require "application_system_test_case"
require_relative "../support/sdk_embed_helper"

class BatchSigningTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include SigningFlowHelper

  test "recipient signs everything awaiting them in one Autogram batch" do
    signer = confirmed_user("signer@example.com")
    first = create_bundle(Tenant.create!(name: "Firma A", plan: :pro), "Zmluva A", "prva.pdf", signer)
    second = create_bundle(Tenant.create!(name: "Firma B", plan: :pro), "Zmluva B", "druha.pdf", signer)
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: SdkEmbedHelper.fake_autogram_app(signed: true))
    sign_in signer

    visit received_bundles_path
    click_on I18n.t("received.autogram_batches.offer.action", count: 2)

    assert_current_path received_bundles_path
    assert first.reload.completed?
    assert second.reload.completed?
    assert_no_link I18n.t("received.autogram_batches.offer.action", count: 2)
  end

  private

  def create_bundle(tenant, name, filename, signer)
    contract = Contract.create!(
      tenant: tenant,
      documents: [ Document.new(blob: pdf_blob(filename)) ],
      allowed_methods: [ "qes" ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    Bundle.create!(tenant: tenant, name: name, contracts: [ contract ]).tap do |bundle|
      bundle.recipients.create!(email: signer.email)
    end
  end
end
