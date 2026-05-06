require "test_helper"

class Contracts::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @contract, @session = create_contract_with_session
  end

  test "download is forbidden without token or authorized user" do
    get "/contracts/#{@contract.uuid}/sessions/#{@session.id}/download"

    assert_response :forbidden
  end

  test "upload is forbidden without token or authorized user" do
    post "/contracts/#{@contract.uuid}/sessions/#{@session.id}/upload", params: {
      signed_document: Base64.strict_encode64("forged")
    }

    assert_response :forbidden
  end

  test "download succeeds with valid session token" do
    token = SessionAccessToken.generate(contract: @contract, session: @session)

    get "/contracts/#{@contract.uuid}/sessions/#{@session.id}/download", params: {
      session_token: token
    }

    assert_response :success
  end

  test "destroy is forbidden without authorized user" do
    session_id = @session.id

    delete "/contracts/#{@contract.uuid}/sessions/#{session_id}"

    assert_response :forbidden
    assert Session.exists?(session_id)
  end

  private

  def create_contract_with_session
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "session-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.new(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    contract.save!

    signer = AnonymousSigner.create!
    signer_contract = signer.signer_contracts.create!(contract: contract)
    session = signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current
    )

    [ contract, session ]
  end
end
