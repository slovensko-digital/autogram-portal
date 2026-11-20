require "test_helper"

class SigningMethodChoiceTest < ActionDispatch::IntegrationTest
  test "embedded signing of a single document that can be signed only electronically goes straight to the signing apps" do
    bundle = create_public_bundle(contracts_count: 1)
    contract = bundle.contracts.sole

    get sign_bundle_path(bundle, iframe: "no_onboarding")

    assert_redirected_to signature_apps_contract_path(contract, iframe: "no_onboarding")

    follow_redirect!

    assert_response :success
    # named on the skipped signing page otherwise
    assert_select "p", text: "document.pdf"
    # going back would only redirect here again
    assert_select "a[href^=?]", sign_bundle_path(bundle), count: 0
  end

  test "embedded signing of a single contract that can be signed only electronically goes straight to the signing apps" do
    contract = create_contract

    get sign_contract_path(contract, iframe: "no_preview")

    assert_redirected_to signature_apps_contract_path(contract, iframe: "no_preview")
  end

  test "embedded signing offers the choice of signing method when there are more methods" do
    bundle = create_public_bundle(contracts_count: 1, allowed_methods: %w[qes ades])
    recipient = bundle.recipients.create!(email: "signer@example.com", locale: "sk")

    get sign_bundle_path(bundle, recipient: recipient.uuid, iframe: "no_onboarding")

    assert_response :success
    assert_select "input[type=radio][value=electronic]"
    assert_select "input[type=radio][value=ades]"
  end

  test "embedded signing of more documents offers each of them with the back link from the signing apps" do
    bundle = create_public_bundle(contracts_count: 2)
    contract = bundle.contracts.first

    get sign_bundle_path(bundle, iframe: "no_onboarding")

    assert_response :success
    assert_select "input[type=radio][value=electronic]", count: 2

    get signature_apps_contract_path(contract, iframe: "no_onboarding")

    assert_select "a[href^=?]", sign_bundle_path(bundle), text: I18n.t("actions.back")
  end

  test "signing pages showing the document preview keep the choice of signing method" do
    bundle = create_public_bundle(contracts_count: 1)

    get sign_bundle_path(bundle, iframe: "true")
    assert_response :success
    assert_select "input[type=radio][value=electronic]"

    get sign_bundle_path(bundle)
    assert_response :success
    assert_select "input[type=radio][value=electronic]"
  end

  private

  def create_public_bundle(contracts_count:, allowed_methods: %w[qes])
    contracts = contracts_count.times.map { create_contract(allowed_methods: allowed_methods) }

    Bundle.create!(tenant: tenants(:one), publicly_visible: true, contracts: contracts)
  end

  def create_contract(allowed_methods: %w[qes])
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 #{SecureRandom.hex(4)}"), filename: "document.pdf", content_type: "application/pdf")

    Contract.create!(
      allowed_methods: allowed_methods,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
  end
end
