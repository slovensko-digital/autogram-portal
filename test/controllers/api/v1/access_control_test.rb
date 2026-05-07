require "test_helper"
require "jwt"
require "openssl"

class Api::V1::AccessControlTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @other = users(:two)

    @owner_key = attach_api_public_key!(@owner)
    @other_key = attach_api_public_key!(@other)

    @owner_contract = create_contract_for(@owner, filename: "owner.pdf")
    @other_contract = create_contract_for(@other, filename: "other.pdf")

    @owner_document = @owner_contract.documents.first
    @other_document = @other_contract.documents.first
  end

  test "api contract show rejects cross-user access" do
    get "/api/v1/contracts/#{@other_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :not_found
  end

  test "api contract show allows owner access" do
    get "/api/v1/contracts/#{@owner_contract.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :success
  end

  test "api document show rejects cross-user access" do
    get "/api/v1/documents/#{@other_document.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :not_found
  end

  test "api document show allows owner access" do
    get "/api/v1/documents/#{@owner_document.uuid}", headers: bearer_headers_for(@owner, @owner_key)

    assert_response :success
  end

  private

  def attach_api_public_key!(user)
    key = OpenSSL::PKey::RSA.generate(2048)
    user.update_column(:api_token_public_key, key.public_key.to_pem)
    key
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

  def create_contract_for(user, filename:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: filename,
      content_type: "application/pdf"
    )

    contract = Contract.new(
      user: user,
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
