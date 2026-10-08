require "application_system_test_case"
require_relative "../support/sdk_embed_helper"

class AutogramSigningTest < ApplicationSystemTestCase
  include SigningFlowHelper

  test "several documents go to Autogram with the signature form and profile of the v1 API" do
    contract = Contract.create!(
      tenant: Tenant.create!(name: "Firma A", plan: :pro),
      allowed_methods: [ "qes" ],
      signature_parameters_attributes: { format: "XAdES", level: "BASELINE_T", container: "ASiC_E" },
      documents_attributes: [ { blob: pdf_blob("zmluva.pdf") }, { blob: pdf_blob("priloha.pdf") } ]
    )
    bundle = Bundle.create!(tenant: contract.tenant, contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "signer@example.com")
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: SdkEmbedHelper.fake_autogram_app(signed: true))

    visit autogram_contract_sessions_path(contract, recipient: recipient.uuid)

    assert_text I18n.t("contracts.sessions.signed.title")
    assert_equal({ "form" => "XAdES", "profile" => "BASELINE_T", "container" => "ASiC_E", "en319132" => false },
                 page.evaluate_script("window.agpSignV1Parameters"))
  end
end
