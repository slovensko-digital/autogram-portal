require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "download rejects numeric document ID" do
    document = create_test_document

    get "/documents/#{document.id}/download"

    assert_response :not_found
  end

  test "download accepts UUID document ID" do
    document = create_test_document

    get "/documents/#{document.uuid}/download"

    assert_response :redirect
  end

  private

  def create_test_document
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test"),
      filename: "test.pdf",
      content_type: "application/pdf"
    )

    Document.create!(blob: blob, uuid: SecureRandom.uuid)
  end
end
