require "test_helper"
require "jwt"
require_relative "../support/cms_signed_document_helper"

# A PDF signed in an enveloping CMS (CAdES without a container) cannot be signed further,
# so Autogram Portal only shows, validates and extends it.
class CmsSignedDocumentFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include CmsSignedDocumentHelper

  test "anonymous upload shows the signed document for validation only" do
    with_cms_validation_service do
      post contracts_path, params: { document: { blob: cms_signed_upload }, contract: { agree_to_policies: "1" } }

      contract = Contract.order(:id).last
      assert_redirected_to contract_path(contract)
      assert_equal SIGNED_PDF_CONTENT, contract.documents.sole.content

      get contract_path(contract)

      assert_response :success
      assert_includes response.body, I18n.t("documents.new.actions.signing_unsupported.title")
      assert_select "input[name='document_action'][value='sign']", count: 0
      assert_select "input[name='document_action'][value='request_signature']", count: 0
      assert_select "a[data-radio-link-target='link']", count: 0
      assert_select "turbo-frame#document_visualization_#{contract.documents.sole.uuid}", count: 1
    end
  end

  test "owner can add a timestamp but cannot sign or request signatures" do
    user = users(:one)
    user.update_column(:confirmed_at, Time.current)
    sign_in user

    with_cms_validation_service do
      contract = create_cms_contract(tenant: tenants(:one))

      get contract_path(contract)

      assert_response :success
      assert_select "input[name='document_action'][value='sign']", count: 0
      assert_select "input[name='document_action'][value='request_signature']", count: 0
      assert_select "input[name='document_action'][value='add_timestamp'][checked]", count: 1
      assert_select "a[data-radio-link-target='link'][href=?]", signature_extension_contract_path(contract, target_level: "T"), count: 1

      get signature_parameters_contract_path(contract, target_step: "request_signature")
      assert_redirected_to contract_path(contract)

      assert_no_difference -> { Bundle.count } do
        patch contract_path(contract), params: { next_step: "request_signature", contract: { allowed_methods: [ "qes" ] } }
      end
      assert_redirected_to contract_path(contract)
      assert_equal I18n.t("contracts.alerts.signing_unsupported"), flash[:alert]
    end
  end

  test "signing pages and sessions are not available" do
    with_cms_validation_service do
      contract = create_cms_contract

      get sign_contract_path(contract)
      assert_redirected_to contract_path(contract)
      assert_equal I18n.t("contracts.alerts.signing_unsupported"), flash[:alert]

      get signature_apps_contract_path(contract)
      assert_redirected_to contract_path(contract)

      get signature_parameters_contract_path(contract, target_step: "sign")
      assert_redirected_to contract_path(contract)

      assert_no_difference -> { Session.count } do
        get "/contracts/#{contract.uuid}/sessions/autogram"
      end
      assert_response :unprocessable_entity
      assert_includes response.body, I18n.t("contracts.alerts.signing_unsupported")
    end
  end

  test "validation shows the CAdES signature of the uploaded CMS" do
    with_cms_validation_service do
      contract = create_cms_contract

      get validate_contract_path(contract)

      assert_response :success
      assert_includes response.body, "Autogram Test"
      assert_includes response.body, I18n.t("signature_parameters.format.cades_without_container")
    end
  end

  test "API rejects a document that cannot be signed" do
    tenant = tenants(:one)
    key = OpenSSL::PKey::RSA.generate(2048)
    tenant.update_columns(api_token_public_key: key.public_to_pem, features: [ "api" ])
    token = JWT.encode({ sub: tenant.id.to_s, exp: 10.minutes.from_now.to_i, jti: SecureRandom.hex(16) }, key, "RS256")

    with_cms_validation_service do
      assert_no_difference -> { Contract.count } do
        post "/api/v1/contracts",
             params: {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [ { filename: "pdf_cades.pdf", content: Base64.strict_encode64(cms_signed_content), contentType: "application/pdf;base64" } ]
             },
             headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body.fetch("errors"), I18n.t("activerecord.errors.models.contract.attributes.base.signing_unsupported")
  end

  test "extending the signatures keeps the CMS format" do
    with_validation_service(ExtendingCmsValidationService.new) do
      contract = create_cms_contract(tenant: tenants(:one))

      contract.extend_signatures!(target_level: "T")

      version = contract.reload.latest_content_version
      assert_equal "extension", version.origin
      assert_equal "pdf_cades.pdf", version.filename
      assert_equal CmsSignedDocumentExtractor::CONTENT_TYPE, version.content_type
    end
  end

  private

  def create_cms_contract(tenant: nil)
    Contract.create!(
      tenant: tenant,
      allowed_methods: [ "qes" ],
      documents: [ Document.new(blob: cms_signed_upload) ]
    )
  end

  class ExtendingCmsValidationService < CmsValidationService
    def extend_signatures(document, target_level:)
      document.content
    end
  end
end
