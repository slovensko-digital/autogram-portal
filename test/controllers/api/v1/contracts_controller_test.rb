require "test_helper"
require "jwt"
require "openssl"

class Api::V1::ContractsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = tenants(:one)
    @key = OpenSSL::PKey::RSA.generate(2048)
    @tenant.update_columns(api_token_public_key: @key.public_to_pem, features: [ "api" ])
  end

  test "contract without documents is rejected as invalid" do
    assert_no_difference -> { Contract.count } do
      post api_v1_contracts_path, params: { id: SecureRandom.uuid, allowedMethods: [ "qes" ] }, headers: bearer_headers, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body.fetch("errors"), "Documents must have at least one document"
  end

  test "bundle with a contract without documents is rejected as invalid" do
    assert_no_difference -> { Bundle.count } do
      post api_v1_bundles_path,
           params: { id: SecureRandom.uuid, publiclyVisible: true, contracts: [ { id: SecureRandom.uuid, allowedMethods: [ "qes" ] } ] },
           headers: bearer_headers, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "contract with an id that already exists is rejected as a conflict" do
    id = SecureRandom.uuid
    post api_v1_contracts_path, params: contract_payload(id), headers: bearer_headers, as: :json
    assert_response :created

    assert_no_difference -> { Contract.count } do
      post api_v1_contracts_path, params: contract_payload(id), headers: bearer_headers, as: :json
    end

    assert_response :conflict
    assert_equal({ "error" => "Contract with the given ID already exists" }, response.parsed_body)
  end

  test "bundle with a contract id that already exists is rejected as a conflict" do
    id = SecureRandom.uuid
    post api_v1_contracts_path, params: contract_payload(id), headers: bearer_headers, as: :json
    assert_response :created

    assert_no_difference -> { Bundle.count } do
      post api_v1_bundles_path, params: { id: SecureRandom.uuid, contracts: [ contract_payload(id) ] }, headers: bearer_headers, as: :json
    end

    assert_response :conflict
    assert_equal({ "error" => "Contract with the given ID already exists" }, response.parsed_body)
  end

  private

  def contract_payload(id)
    {
      id: id,
      allowedMethods: [ "qes" ],
      documents: [ { filename: "zmluva.pdf", content: Base64.strict_encode64("%PDF-1.4 zmluva"), contentType: "application/pdf;base64" } ]
    }
  end

  def bearer_headers
    token = JWT.encode({ sub: @tenant.id.to_s, exp: 10.minutes.from_now.to_i, jti: SecureRandom.hex(16) }, @key, "RS256")
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end
