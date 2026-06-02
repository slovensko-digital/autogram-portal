require "test_helper"
require "jwt"
require "openssl"

class Api::V1::BundlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @owner.update_column(:email, "owner@example.com")
    @owner_key = OpenSSL::PKey::RSA.generate(2048)
    @owner.update_column(:api_token_public_key, @owner_key.public_to_pem)
  end

  test "public bundle sign route falls back to full-page electronic setup when onboarding is still needed" do
    post "/api/v1/bundles",
         params: {
           id: SecureRandom.uuid,
           publiclyVisible: true,
           contracts: [
             {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [
                 {
                   filename: "contract.txt",
                   content: Base64.strict_encode64("Sample text content"),
                   contentType: "text/plain;base64"
                 }
               ],
               signatureParameters: {
                 format: "XAdES",
                 container: "ASiC_E"
               }
             }
           ]
         },
         headers: bearer_headers_for(@owner, @owner_key)

    assert_response :created

    bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
    assert bundle.publicly_visible?

    get "/bundles/#{bundle.uuid}/sign"

    assert_response :success
    assert_select "button[data-signing-method-target='continueButton']", count: 0

    contract = bundle.contracts.first
    assert_select "turbo-frame##{"signature_apps_#{contract.uuid}"}[src]", count: 0
    assert_select "a[href='/contracts/#{contract.uuid}/sessions/autogram']", count: 0
    assert_select "a[href*='/contracts/#{contract.uuid}/signature_apps']", text: "Pokračovať"
  end

  test "public bundle sign route loads embedded signature apps directly in no_onboarding mode" do
    post "/api/v1/bundles",
         params: {
           id: SecureRandom.uuid,
           publiclyVisible: true,
           contracts: [
             {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [
                 {
                   filename: "contract.txt",
                   content: Base64.strict_encode64("Sample text content"),
                   contentType: "text/plain;base64"
                 }
               ],
               signatureParameters: {
                 format: "XAdES",
                 container: "ASiC_E"
               }
             }
           ]
         },
         headers: bearer_headers_for(@owner, @owner_key)

    assert_response :created

    bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
    assert_not bundle.author_notifications_enabled?
    contract = bundle.contracts.first

    get "/bundles/#{bundle.uuid}/sign", params: { iframe: "no_onboarding" }

    assert_response :success
    assert_select "button[data-signing-method-target='continueButton']", count: 0
    assert_select "turbo-frame##{"signature_apps_#{contract.uuid}"}[src*='/contracts/#{contract.uuid}/signature_apps'][src*='embedded=true'][src*='iframe=no_onboarding']"
  end

  test "public bundle sign route stays available when bundle only has an author proxy recipient" do
    post "/api/v1/bundles",
         params: {
           id: SecureRandom.uuid,
           publiclyVisible: true,
           contracts: [
             {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [
                 {
                   filename: "contract.txt",
                   content: Base64.strict_encode64("Sample text content"),
                   contentType: "text/plain;base64"
                 }
               ],
               signatureParameters: {
                 format: "XAdES",
                 container: "ASiC_E"
               }
             }
           ]
         },
         headers: bearer_headers_for(@owner, @owner_key)

    assert_response :created

    bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
    contract = bundle.contracts.first
    Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: @owner)

    get "/bundles/#{bundle.uuid}/sign", params: { iframe: "no_onboarding" }

    assert_response :success
    assert_select "button[data-signing-method-target='continueButton']", count: 0
    assert_select "turbo-frame##{"signature_apps_#{contract.uuid}"}[src*='/contracts/#{contract.uuid}/signature_apps'][src*='embedded=true'][src*='iframe=no_onboarding']"
  end

  test "public bundle sign route offers autogram desktop batch signing for multiple contracts" do
    post "/api/v1/bundles",
         params: {
           id: SecureRandom.uuid,
           publiclyVisible: true,
           contracts: 2.times.map do |index|
             {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [
                 {
                   filename: "contract-#{index}.txt",
                   content: Base64.strict_encode64("Sample text content #{index}"),
                   contentType: "text/plain;base64"
                 }
               ],
               signatureParameters: {
                 format: "XAdES",
                 container: "ASiC_E"
               }
             }
           end
         },
         headers: bearer_headers_for(@owner, @owner_key)

    assert_response :created

    bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))

    get "/bundles/#{bundle.uuid}/sign", params: { iframe: "no_onboarding" }

    assert_response :success
    assert_select "a[href='/bundles/#{bundle.uuid}/autogram_batch?iframe=no_onboarding']"
    assert_select "button[data-signing-method-target='continueButton']", count: 0
    assert_select "section.border-t", count: 2
    assert_select "span.inline-flex.shrink-0.whitespace-nowrap.rounded-full", count: 2
    assert_not_includes response.body, "first:border-t-0"
    assert_includes response.body, I18n.t("bundles.sign.batch_sign_recommended")
    assert_includes response.body, I18n.t("bundles.sign.individual_signing_hint_title")
    assert_includes response.body, I18n.t("bundles.sign.individual_signing_hint")
    assert_includes response.body, I18n.t("bundles.sign.individual_signing_section_badge")
    assert_includes response.body, I18n.t("bundles.sign.individual_signing_section_title")
    assert_includes response.body, I18n.t("bundles.sign.individual_signing_section_description")
    assert_includes response.body, "contract-0.txt"
    assert_includes response.body, "contract-1.txt"
    bundle.contracts.each do |contract|
      assert_select "turbo-frame##{"signature_apps_#{contract.uuid}"}[src*='/contracts/#{contract.uuid}/signature_apps'][src*='embedded=true'][src*='iframe=no_onboarding']"
    end

    get "/bundles/#{bundle.uuid}/autogram_batch", params: { iframe: "no_onboarding" }

    assert_response :success
    assert_includes response.body, 'data-controller="signers--autogram-batch"'
    assert_select "main h1", text: I18n.t("bundles.autogram_batch.title"), count: 0
    assert_select "main p", text: Regexp.new(Regexp.escape(I18n.t("bundles.autogram_batch.subtitle", count: 2))), count: 0
    assert_includes response.body, I18n.t("bundles.autogram_batch.waiting_for_app")
    assert_includes response.body, I18n.t("bundles.sign.batch_sign_unavailable")
    assert_includes response.body, I18n.t("bundles.autogram_batch.step1_title")
    assert_includes response.body, I18n.t("bundles.autogram_batch.step2_title")
    assert_includes response.body, I18n.t("bundles.autogram_batch.step4_title")
    assert_includes response.body, I18n.t("bundles.autogram_batch.status_checking")
    assert_includes response.body, I18n.t("bundles.autogram_batch.status_waiting")
    assert_includes response.body, I18n.t("bundles.autogram_batch.progress_subtitle")
    assert_includes response.body, I18n.t("bundles.autogram_batch.documents_toggle", count: 2)
    assert_includes response.body, I18n.t("bundles.autogram_batch.documents_description")
    assert_includes response.body, ActionController::Base.helpers.asset_path("autogram-sdk.js")
    assert_select "[data-signers--autogram-batch-target='statusChecking']", count: 1
    assert_select "[data-signers--autogram-batch-target='statusWaiting']", count: 1
    assert_select "details li[data-signers--autogram-batch-target='documentItem']", count: 2
  end

  test "public bundle sign route hides autogram desktop batch signing on mobile" do
    post "/api/v1/bundles",
         params: {
           id: SecureRandom.uuid,
           publiclyVisible: true,
           contracts: 2.times.map do |index|
             {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [
                 {
                   filename: "contract-#{index}.txt",
                   content: Base64.strict_encode64("Sample text content #{index}"),
                   contentType: "text/plain;base64"
                 }
               ],
               signatureParameters: {
                 format: "XAdES",
                 container: "ASiC_E"
               }
             }
           end
         },
         headers: bearer_headers_for(@owner, @owner_key)

    assert_response :created

    bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))

    get "/bundles/#{bundle.uuid}/sign", params: { iframe: "no_onboarding" }, headers: { "User-Agent" => "iPhone" }

    assert_response :success
    assert_select "a[href='/bundles/#{bundle.uuid}/autogram_batch?iframe=no_onboarding']", count: 0
    assert_includes response.body, I18n.t("bundles.sign.mobile_individual_signing_title")
    assert_includes response.body, I18n.t("bundles.sign.mobile_individual_signing_description")

    get "/bundles/#{bundle.uuid}/autogram_batch", params: { iframe: "no_onboarding" }, headers: { "User-Agent" => "iPhone" }

    assert_redirected_to "/bundles/#{bundle.uuid}/sign?iframe=no_onboarding"
  end

  test "bundle signing method choice falls back to top-level onboarding when electronic setup is missing" do
    with_allowed_methods(%w[qes scan]) do
      post "/api/v1/bundles",
           params: {
             id: SecureRandom.uuid,
             publiclyVisible: true,
             contracts: [
               {
                 id: SecureRandom.uuid,
                 allowedMethods: [ "qes", "scan" ],
                 documents: [
                   {
                     filename: "contract.txt",
                     content: Base64.strict_encode64("Sample text content"),
                     contentType: "text/plain;base64"
                   }
                 ],
                 signatureParameters: {
                   format: "XAdES",
                   container: "ASiC_E"
                 }
               }
             ]
           },
           headers: bearer_headers_for(@owner, @owner_key)

      assert_response :created

      bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
      contract = bundle.contracts.first

      get "/bundles/#{bundle.uuid}/sign"

      assert_response :success
      assert_select "button[data-signing-method-target='continueButton']", count: 1
      assert_select "a[data-signing-method-target='electronicButton'][href*='/contracts/#{contract.uuid}/signature_apps'][data-turbo-frame='_top']"
    end
  end

  test "bundle signing method choice keeps embedded signing app selector in no_onboarding mode" do
    with_allowed_methods(%w[qes scan]) do
      post "/api/v1/bundles",
           params: {
             id: SecureRandom.uuid,
             publiclyVisible: true,
             contracts: [
               {
                 id: SecureRandom.uuid,
                 allowedMethods: [ "qes", "scan" ],
                 documents: [
                   {
                     filename: "contract.txt",
                     content: Base64.strict_encode64("Sample text content"),
                     contentType: "text/plain;base64"
                   }
                 ],
                 signatureParameters: {
                   format: "XAdES",
                   container: "ASiC_E"
                 }
               }
             ]
           },
           headers: bearer_headers_for(@owner, @owner_key)

      assert_response :created

      bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
      contract = bundle.contracts.first

      get "/bundles/#{bundle.uuid}/sign", params: { iframe: "no_onboarding" }

      assert_response :success
      assert_select "button[data-signing-method-target='continueButton']", count: 1
      assert_select "a[data-signing-method-target='electronicButton'][href*='embedded=true'][href*='iframe=no_onboarding'][data-turbo-frame='signature_apps_#{contract.uuid}']"
    end
  end

  private

  def with_allowed_methods(methods)
    original_allowed_methods = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, methods)

    yield
  ensure
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, original_allowed_methods)
  end

  def bearer_headers_for(user, key)
    token = JWT.encode(
      {
        sub: user.id.to_s,
        exp: 10.minutes.from_now.to_i,
        jti: SecureRandom.hex(16)
      },
      key,
      "RS256"
    )

    {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    }
  end
end
