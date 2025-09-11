require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @document = Document.create!(
      user: @user,
      uuid: SecureRandom.uuid
    )

    # Attach a mock file
    @document.blob.attach(
      io: StringIO.new("fake pdf content"),
      filename: "test-signed.pdf",
      content_type: "application/pdf"
    )
  end

  test "should get show" do
    get document_url(@document)
    assert_response :success
  end

  test "should get validate with signatures" do
    get validate_document_url(@document)
    assert_response :success

    json_response = JSON.parse(response.body)

    assert json_response.key?('hasSignatures')
    assert json_response.key?('signatures')
    assert json_response.key?('documentInfo')
    assert json_response.key?('errors')

    # Since filename contains 'signed', mock should return signatures
    assert json_response['hasSignatures']
    assert_equal 1, json_response['signatures'].length

    signature = json_response['signatures'].first
    assert_equal "Ján Novák", signature['signerName']
    assert_equal "PAdES_BASELINE_B", signature['signatureLevel']
    assert_equal "TOTAL_PASSED", signature['validationResult']
    assert signature['valid']
  end

  test "should get validate without signatures" do
    # Create a file without 'signed' in filename
    @document.blob.purge
    @document.blob.attach(
      io: StringIO.new("fake pdf content"),
      filename: "regular-document.pdf",
      content_type: "application/pdf"
    )

    get validate_document_url(@document)
    assert_response :success

    json_response = JSON.parse(response.body)

    assert_not json_response['hasSignatures']
    assert_equal 0, json_response['signatures'].length
  end
end
