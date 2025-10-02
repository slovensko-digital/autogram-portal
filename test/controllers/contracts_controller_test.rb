require "test_helper"

class ContractsControllerTest < ActionDispatch::IntegrationTest
  test "should destroy contract and redirect to index" do
    # Create a contract for testing
    contract = Contract.create!(
      uuid: SecureRandom.uuid,
      allowed_methods: %w[qes ts-qes]
    )

    # Create signature parameters (required by validation)
    contract.create_signature_parameters!(
      format_container_combination: "pdf",
      add_content_timestamp: false
    )

    # Create a document with blob
    document = contract.documents.create!(
      uuid: SecureRandom.uuid
    )

    # Attach a test file blob
    document.blob.attach(
      io: StringIO.new("test content"),
      filename: "test.pdf",
      content_type: "application/pdf"
    )

    # Ensure the contract and document exist
    assert Contract.exists?(contract.id)
    assert Document.exists?(document.id)

    # Count contracts and documents before deletion
    contracts_count = Contract.count
    documents_count = Document.count

    # Perform the destroy action
    delete contract_path(contract)

    # Check redirect
    assert_redirected_to contracts_path

    # Check that contract and its documents are deleted
    assert_not Contract.exists?(contract.id)
    assert_not Document.exists?(document.id)

    # Verify counts have decreased
    assert_equal contracts_count - 1, Contract.count
    assert_equal documents_count - 1, Document.count
  end
end
