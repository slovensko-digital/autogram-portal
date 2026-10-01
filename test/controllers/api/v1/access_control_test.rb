require "test_helper"
require "jwt"
require "openssl"

class Api::V1::AccessControlTest < ActionDispatch::IntegrationTest
  setup do
    @owner = tenants(:one)
    @other = tenants(:two)

    @owner_key = attach_api_public_key!(@owner)
    @other_key = attach_api_public_key!(@other)

    @owner_contract = create_contract_for(@owner, filename: "owner.pdf")
    @other_contract = create_contract_for(@other, filename: "other.pdf")

    @owner_document = @owner_contract.documents.first
    @other_document = @other_contract.documents.first
  end

  test "api contract show rejects cross-tenant access" do
    get "/api/v1/contracts/#{@other_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :not_found
  end

  test "api contract show allows owner access" do
    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :success
  end

  test "api contract and document access use direct or bundle tenant ownership" do
    Bundle.create!(tenant: @owner, contracts: [ @other_contract ])
    @other_contract.update_column(:tenant_id, @other.id)

    [ [ @owner, @owner_key ], [ @other, @other_key ] ].each do |tenant, key|
      get "/api/v1/contracts/#{@other_contract.uuid}", headers: bearer_headers_for(tenant, key)
      assert_response :success

      get "/api/v1/documents/#{@other_document.uuid}", headers: bearer_headers_for(tenant, key)
      assert_response :success
    end
  end

  test "api contract deletion rejects foreign tenant without mutation" do
    assert_no_difference -> { Contract.count } do
      delete "/api/v1/contracts/#{@other_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key)
    end

    assert_response :not_found
    assert_equal({ "error" => "Contract not found" }, response.parsed_body)
  end

  test "api bundle access remains tenant scoped even when publicly visible" do
    bundle = Bundle.create!(tenant: @other, contracts: [ @other_contract ], publicly_visible: true)
    headers = bearer_headers_for(@owner, @owner_key)

    get "/api/v1/bundles/#{bundle.uuid}", headers: headers
    assert_response :not_found
    assert_equal({ "error" => "Bundle not found" }, response.parsed_body)

    assert_no_difference -> { Bundle.count } do
      delete "/api/v1/bundles/#{bundle.uuid}", headers: headers
    end
    assert_response :not_found
  end

  test "api hello remains public without a tenant token" do
    get "/api/v1/hello"

    assert_response :success
    assert_equal({ "message" => "Hello, World!" }, response.parsed_body)
  end

  test "api document show rejects cross-tenant access" do
    get "/api/v1/documents/#{@other_document.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :not_found
  end

  test "api document show allows owner access" do
    get "/api/v1/documents/#{@owner_document.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :success
  end

  test "api contract show allows owner access with ES256 token" do
    owner_ec_key = attach_api_public_key!(@owner, algorithm: "ES256")

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner, owner_ec_key, algorithm: "ES256")

    assert_response :success
  end

  test "api contract show allows owner access with RS256 token" do
    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key, algorithm: "RS256")

    assert_response :success
  end

  test "api returns 401 for token with non matching algorithm to tenant key" do
    unsupported_key = OpenSSL::PKey::EC.generate("prime256v1")

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner, unsupported_key, algorithm: "ES256")

    assert_response :unauthorized
  end

  test "api returns 401 when the tenant has api access disabled" do
    @owner.update_column(:features, [])

    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :unauthorized
  end

  test "api hello_auth identifies the tenant" do
    get "/api/v1/hello_auth", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :success
    assert_equal "Hello, #{@owner.id}!", response.parsed_body["message"]
  end

  private

  def attach_api_public_key!(tenant, algorithm: "RS256")
    key = case algorithm
    when "ES256"
      OpenSSL::PKey::EC.generate("prime256v1")
    when "RS256"
      OpenSSL::PKey::RSA.generate(2048)
    else
      raise ArgumentError, "Unsupported algorithm: #{algorithm}"
    end

    tenant.update_columns(api_token_public_key: key.public_to_pem, features: [ "api" ])
    key
  end

  def bearer_headers_for(tenant, key, algorithm: "RS256")
    token = JWT.encode(
      {
        sub: tenant.id.to_s,
        exp: 10.minutes.from_now.to_i,
        jti: SecureRandom.hex(16)
      },
      key,
      algorithm
    )

    {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    }
  end

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
