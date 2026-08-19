require "test_helper"
require_relative "api_test_helper"

class Api::V1::AccessControlTest < ActionDispatch::IntegrationTest
  include ApiTestHelper

  setup do
    @owner_tenant = tenants(:one)
    @other_tenant = tenants(:two)
    enable_api_for!(@owner_tenant)
    enable_api_for!(@other_tenant)
    @owner_key = attach_api_key!(tenant: @owner_tenant)
    @other_key = attach_api_key!(tenant: @other_tenant)

    @owner_contract = create_contract_for(@owner_tenant, filename: "owner.pdf")
    @other_contract = create_contract_for(@other_tenant, filename: "other.pdf")

    @owner_document = @owner_contract.documents.first
    @other_document = @other_contract.documents.first
  end

  test "api contract show rejects cross-tenant access" do
    get "/api/v1/contracts/#{@other_contract.uuid}", headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :not_found
  end

  test "api contract status and destroy reject cross-tenant access" do
    headers = bearer_headers_for(@owner_tenant, @owner_key)

    get "/api/v1/contracts/#{@other_contract.uuid}/status", headers: headers
    assert_response :not_found

    delete "/api/v1/contracts/#{@other_contract.uuid}", headers: headers
    assert_response :not_found
    assert Contract.exists?(@other_contract.id)
  end

  test "api contract show allows tenant access" do
    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :success
  end

  test "api document show rejects cross-tenant access" do
    get "/api/v1/documents/#{@other_document.uuid}", headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :not_found
  end

  test "api document show allows tenant access" do
    get "/api/v1/documents/#{@owner_document.uuid}", headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :success
  end

  test "api contract show allows tenant access with ES256 token" do
    owner_ec_key = attach_api_key!(tenant: @owner_tenant, algorithm: "ES256")

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner_tenant, owner_ec_key, algorithm: "ES256")

    assert_response :success
  end

  test "api contract show allows tenant access with RS256 token" do
    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner_tenant, @owner_key, algorithm: "RS256")

    assert_response :success
  end

  test "api returns 401 for token signed with wrong key" do
    wrong_key = OpenSSL::PKey::EC.generate("prime256v1")

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner_tenant, wrong_key, algorithm: "ES256")

    assert_response :unauthorized
  end

  test "api rejects changed key" do
    headers = bearer_headers_for(@owner_tenant, @owner_key)
    @owner_tenant.update_column(:api_token_public_key, OpenSSL::PKey::RSA.generate(2048).public_to_pem)

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: headers

    assert_response :unauthorized
  end

  test "api rejects a key for tenant without api feature" do
    @owner_tenant.update_column(:features, [])

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :unauthorized
  end

  test "api accepts migrated numeric key identifiers" do
    # @owner_tenant has a numeric-style api_token_identifier (legacy user id) from fixture migration
    migrated_key = OpenSSL::PKey::RSA.generate(2048)
    @owner_tenant.update_column(:api_token_public_key, migrated_key.public_to_pem)

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner_tenant, migrated_key)

    assert_response :success
  end

  test "api rejects cleared key" do
    headers = bearer_headers_for(@owner_tenant, @owner_key)
    @owner_tenant.update_column(:api_token_public_key, nil)

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: headers

    assert_response :unauthorized
  end

  test "api bundle actions reject cross-tenant access" do
    other_bundle = bundles(:two)
    other_bundle.update_column(:uuid, SecureRandom.uuid)
    headers = bearer_headers_for(@owner_tenant, @owner_key)

    get "/api/v1/bundles/#{other_bundle.uuid}", headers: headers
    assert_response :not_found

    get "/api/v1/bundles/#{other_bundle.uuid}/status", headers: headers
    assert_response :not_found

    delete "/api/v1/bundles/#{other_bundle.uuid}", headers: headers
    assert_response :not_found
    assert Bundle.exists?(other_bundle.id)
  end

  test "api contract creation assigns tenant" do
    contract_uuid = SecureRandom.uuid

    post "/api/v1/contracts",
      params: {
        id: contract_uuid,
        allowedMethods: [ "qes" ],
        documents: [
          {
            filename: "created.txt",
            content: Base64.strict_encode64("Created through API"),
            contentType: "text/plain;base64"
          }
        ],
        signatureParameters: {
          format: "XAdES",
          container: "ASiC_E"
        }
      },
      headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :created
    contract = Contract.find_by!(uuid: contract_uuid)
    assert_equal @owner_tenant, contract.tenant
  end

  test "hello_auth returns tenant id" do
    get "/api/v1/hello_auth", headers: bearer_headers_for(@owner_tenant, @owner_key)

    assert_response :success
    assert_equal "Hello, #{@owner_tenant.id}!", response.parsed_body["message"]
  end

  private

  def create_contract_for(tenant, filename:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: filename,
      content_type: "application/pdf"
    )

    contract = Contract.new(
      tenant: tenant,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )

    contract.save!
    contract
  end
end
