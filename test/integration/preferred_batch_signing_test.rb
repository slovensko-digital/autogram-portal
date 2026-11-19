require "test_helper"

class PreferredBatchSigningTest < ActionDispatch::IntegrationTest
  test "integrator preferring batch signing gets more documents straight to Autogram with signing them one by one aside" do
    bundle = create_public_bundle(contracts_count: 2)

    get sign_bundle_path(bundle, iframe: "no_onboarding", prefer_batch: "true")

    assert_redirected_to autogram_batch_bundle_path(bundle, iframe: "no_onboarding", prefer_batch: "true")

    follow_redirect!

    assert_response :success
    assert_select "a[href=?]", sign_bundle_path(bundle, iframe: "no_onboarding"), text: I18n.t("bundles.autogram_batch.sign_individually")
    assert_select "a", text: I18n.t("bundles.autogram_batch.back_to_bundle"), count: 0
  end

  test "batch signing opened from the bundle leads back to it" do
    bundle = create_public_bundle(contracts_count: 2)

    get autogram_batch_bundle_path(bundle, iframe: "no_onboarding")

    assert_select "a[href=?]", sign_bundle_path(bundle, iframe: "no_onboarding"), text: I18n.t("bundles.autogram_batch.back_to_bundle")
  end

  test "preferred batch signing is left out where Autogram cannot sign all documents at once" do
    bundle = create_public_bundle(contracts_count: 2)

    get sign_bundle_path(bundle, iframe: "no_onboarding", prefer_batch: "true"), headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)" }
    assert_response :success

    single = create_public_bundle(contracts_count: 1)
    get sign_bundle_path(single, iframe: "no_onboarding", prefer_batch: "true")
    assert_redirected_to signature_apps_contract_path(single.contracts.sole, iframe: "no_onboarding")
  end

  test "bundle without the integrator preferring batch signing offers the choice" do
    bundle = create_public_bundle(contracts_count: 2)

    get sign_bundle_path(bundle, iframe: "no_onboarding")

    assert_response :success
    assert_select "a[href^=?]", autogram_batch_bundle_path(bundle), text: I18n.t("bundles.sign.batch_sign_action")
  end

  private

  def create_public_bundle(contracts_count:)
    contracts = contracts_count.times.map do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 #{SecureRandom.hex(4)}"), filename: "document.pdf", content_type: "application/pdf")
      Contract.create!(allowed_methods: %w[qes], documents_attributes: [ { blob: blob } ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" })
    end

    Bundle.create!(tenant: tenants(:one), publicly_visible: true, contracts: contracts)
  end
end
