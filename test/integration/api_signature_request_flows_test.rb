require "test_helper"
require "jwt"
require "openssl"
require_relative "../support/signing_flow_helper"
require_relative "../support/plan_limits_helper"

# End-to-end signature requests created through the API by an organization and
# signed by recipients through the web.
class ApiSignatureRequestFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SigningFlowHelper
  include PlanLimitsHelper

  setup do
    @api_key = OpenSSL::PKey::RSA.generate(2048)
    @organization = Tenant.create!(name: "Firma ABC", plan: :pro, features: [ "api" ], api_token_public_key: @api_key.public_to_pem)
    @owner = confirmed_user("owner@firma-abc.sk", tenant: @organization, role: :owner)
  end

  test "recipient signs a bundle of several documents one by one and it completes after the last" do
    bundle = create_bundle_via_api(
      contracts: [ pdf_contract_payload("prva.pdf"), pdf_contract_payload("druha.pdf"), pdf_contract_payload("tretia.pdf") ],
      recipients: [ { email: "signer@example.com" } ]
    )
    recipient = bundle.recipients.sole
    contracts = bundle.contracts.order(:id).to_a
    assert_equal 3, contracts.size

    get autogram_batch_bundle_path(bundle, recipient: recipient.uuid)
    assert_response :success
    contracts.each { |contract| assert_includes response.body, contract.uuid }

    contracts.first(2).each do |contract|
      sign_with_autogram(contract, recipient: recipient)
      assert_not bundle.reload.completed?
      assert recipient.reload.pending?
    end

    sign_with_autogram(contracts.last, recipient: recipient)

    assert bundle.reload.completed?
    assert recipient.reload.signed?
    assert contracts.all? { |contract| contract.reload.signed_document_attached? }

    get api_v1_bundle_path(bundle), headers: api_headers
    assert_response :success
  end

  test "contract with several files is signed once as an ASiC-E container" do
    bundle = create_bundle_via_api(
      contracts: [
        {
          id: SecureRandom.uuid,
          allowedMethods: [ "qes" ],
          documents: [ text_document("zmluva.txt", "Zmluva"), text_document("priloha.txt", "Príloha"), text_document("cennik.txt", "Cenník") ],
          signatureParameters: { level: "BASELINE_B", format: "XAdES", container: "ASiC_E" }
        }
      ],
      recipients: [ { email: "signer@example.com" } ]
    )
    contract = bundle.contracts.sole
    recipient = bundle.recipients.sole

    parameters = sign_with_autogram(contract, recipient: recipient)

    assert parameters["multiple_documents"]
    assert_equal %w[zmluva.txt priloha.txt cennik.txt], parameters["documents"].map { |document| document["filename"] }
    assert_equal "ASiC_E", parameters.dig("signature_parameters", "container")
    assert contract.reload.signed_document_attached?
    assert_match(/\.asice\z/, contract.latest_content_version.filename)
    assert bundle.reload.completed?
  end

  test "recipients inside the organization, from another organization and without an account all sign one bundle" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    outsider = confirmed_user("outsider@inafirma.sk")
    bundle = create_bundle_via_api(
      contracts: [ pdf_contract_payload("trojstranna.pdf"), pdf_contract_payload("priloha.pdf") ],
      recipients: [ { email: colleague.email }, { email: outsider.email }, { email: "guest@example.com" } ]
    )
    contracts = bundle.contracts.order(:id).to_a
    by_email = bundle.recipients.index_by(&:email)
    assert_equal colleague, by_email[colleague.email].user
    assert_equal outsider, by_email[outsider.email].user
    assert_nil by_email["guest@example.com"].user

    sign_in_with_tenant colleague, @organization
    get bundles_path
    assert_includes response.body, bundle_path(bundle), "organization members see bundles created through the API"
    contracts.each { |contract| sign_with_autogram(contract) }
    sign_out colleague

    sign_in outsider
    get bundle_path(bundle)
    assert_response :not_found
    contracts.each { |contract| sign_with_autogram(contract) }
    sign_out outsider

    assert_not bundle.reload.completed?

    contracts.each { |contract| sign_with_autogram(contract, recipient: by_email["guest@example.com"]) }

    assert bundle.reload.completed?
    assert bundle.recipients.all?(&:signed?)
    assert_empty bundle.recipients.author_proxies
  end

  test "another organization cannot read the bundle through the API" do
    bundle = create_bundle_via_api(contracts: [ pdf_contract_payload("tajna.pdf") ], recipients: [ { email: "signer@example.com" } ])
    other_key = OpenSSL::PKey::RSA.generate(2048)
    other = Tenant.create!(name: "Iná firma", plan: :pro, features: [ "api" ], api_token_public_key: other_key.public_to_pem)

    get api_v1_bundle_path(bundle), headers: api_headers(tenant: other, key: other_key)

    assert_response :not_found
  end

  test "a document over the size limit is rejected before anything is stored" do
    with_plan_limits("MAX_DOCUMENT_SIZE_MB" => "1") do
      large = Base64.strict_encode64("%PDF-1.4 " + "a" * 1.megabyte)
      payload = pdf_contract_payload("velky.pdf").merge(documents: [ { filename: "velky.pdf", content: large, contentType: "application/pdf;base64" } ])

      assert_no_difference [ "ActiveStorage::Blob.count", "Bundle.count", "Contract.count" ] do
        post api_v1_bundles_path, params: { id: SecureRandom.uuid, contracts: [ payload ], recipients: [ { email: "signer@example.com" } ] }, headers: api_headers, as: :json
      end

      assert_response :unprocessable_entity
      assert_equal "limit_exceeded", response.parsed_body["code"]
      assert_equal "document_size", response.parsed_body["limit"]
    end
  end

  test "all documents of a request must fit the stored documents limit" do
    with_plan_limits("PRO_MAX_STORED_DOCUMENTS" => "2") do
      contracts = [ pdf_contract_payload("a.pdf"), pdf_contract_payload("b.pdf"), pdf_contract_payload("c.pdf") ]

      assert_no_difference [ "ActiveStorage::Blob.count", "Contract.count" ] do
        post api_v1_bundles_path, params: { id: SecureRandom.uuid, contracts: contracts, recipients: [ { email: "signer@example.com" } ] }, headers: api_headers, as: :json
      end
      assert_response :unprocessable_entity
      assert_equal "stored_documents", response.parsed_body["limit"]

      post api_v1_contracts_path, params: pdf_contract_payload("samostatny.pdf"), headers: api_headers, as: :json
      assert_response :created
    end
  end

  test "a bundle created through the API counts when its recipient signs and the usage is reported" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "5", "PRO_MONTHLY_TIMESTAMPS" => nil, "PRO_MAX_STORED_DOCUMENTS" => nil, "PRO_STORAGE_GB" => nil) do
      bundle = create_bundle_via_api(contracts: [ pdf_contract_payload("a.pdf"), pdf_contract_payload("b.pdf") ], recipients: [ { email: "signer@example.com" } ])
      assert_equal 0, @organization.usage_of(:signature_requests), "creating a bundle does not send it"

      first, second = bundle.contracts.order(:id).to_a
      sign_with_autogram(first, recipient: bundle.recipients.sole)
      assert_equal 1, @organization.usage_of(:signature_requests), "only the signed document counts"
      sign_with_autogram(second, recipient: bundle.recipients.sole)

      get api_v1_usage_path, headers: api_headers
      assert_response :success
      usage = response.parsed_body
      assert_equal "pro", usage["plan"]
      assert_equal({ "used" => 2, "limit" => 5 }, usage.dig("usage", "signatureRequests"))
      assert_equal({ "used" => 0, "limit" => nil }, usage.dig("usage", "timestamps"))
      assert_equal 2, usage.dig("usage", "storedDocuments", "used")
      assert usage.dig("usage", "storage", "used").positive?
    end
  end

  test "a contract created through the API outside a bundle counts when someone signs it" do
    post api_v1_contracts_path, params: pdf_contract_payload("samostatna.pdf"), headers: api_headers, as: :json
    assert_response :created, -> { response.body }
    contract = Contract.find_by!(uuid: response.parsed_body.fetch("id"))
    assert_nil contract.bundle
    assert_equal 0, @organization.usage_of(:signature_requests)

    sign_with_autogram(contract)

    assert_equal [ "standalone_signature" ], @organization.usage_records.signature_request.pluck(:source)
  end

  test "status of a contract created through the API leads to its API details once it is signed" do
    post api_v1_contracts_path, params: pdf_contract_payload("stav.pdf"), headers: api_headers, as: :json
    assert_response :created, -> { response.body }
    contract = Contract.find_by!(uuid: response.parsed_body.fetch("id"))

    get status_api_v1_contract_path(contract), headers: api_headers
    assert_response :ok

    sign_with_autogram(contract)

    get status_api_v1_contract_path(contract), headers: api_headers
    assert_redirected_to api_v1_contract_path(contract)

    get response.location, headers: api_headers
    assert_response :success
    assert_equal contract.uuid, response.parsed_body.fetch("id")
    assert response.parsed_body["signed_document"].present?
  end

  test "usage is reported only to a tenant with an API token" do
    get api_v1_usage_path

    assert_response :unauthorized
  end

  test "a bundle signed on paper shows the approved scan and the integrator downloads it" do
    with_scan_allowed do
      bundle = create_bundle_via_api(contracts: [ scan_contract_payload("a.pdf") ], recipients: [ { email: "signer@example.com" } ])
      recipient = bundle.recipients.sole
      paper = paper_signature_for(bundle.contracts.sole, recipient, approve: true)

      get api_v1_bundle_path(bundle), headers: api_headers
      assert_response :success
      contract_json = response.parsed_body["contracts"].sole
      assert_nil contract_json["signed_document"]
      assert contract_json.key?("signed_document")
      item = contract_json["paper_signatures"].sole
      assert_equal %w[approved_at recipient scan status submitted_at], item.keys.sort
      assert_equal [ recipient.uuid, "approved" ], item.values_at("recipient", "status")
      assert_equal paper.reviewed_at.iso8601(3), Time.zone.parse(item["approved_at"]).iso8601(3)
      assert_equal scan_api_v1_contract_paper_signature_url(bundle.contracts.sole, paper), item["scan"]

      get URI(item["scan"]).path, headers: api_headers
      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert_match(/attachment/, response.headers["Content-Disposition"])
      assert_equal paper.scan.download, response.body
    end
  end

  test "another organization cannot download the scan" do
    with_scan_allowed do
      bundle = create_bundle_via_api(contracts: [ scan_contract_payload("a.pdf") ], recipients: [ { email: "signer@example.com" } ])
      paper = paper_signature_for(bundle.contracts.sole, bundle.recipients.sole, approve: true)
      other_key = OpenSSL::PKey::RSA.generate(2048)
      other = Tenant.create!(name: "Iná", plan: :pro, features: [ "api" ], api_token_public_key: other_key.public_to_pem)

      get scan_api_v1_contract_paper_signature_path(bundle.contracts.sole, paper), headers: api_headers(tenant: other, key: other_key)
      assert_response :not_found
    end
  end

  test "a returned paper signature has no scan endpoint" do
    with_scan_allowed do
      bundle = create_bundle_via_api(contracts: [ scan_contract_payload("a.pdf") ], recipients: [ { email: "signer@example.com" } ])
      paper = paper_signature_for(bundle.contracts.sole, bundle.recipients.sole)
      paper.return!(@owner, "unreadable")

      get scan_api_v1_contract_paper_signature_path(bundle.contracts.sole, paper), headers: api_headers
      assert_response :not_found
      get api_v1_contract_path(bundle.contracts.sole), headers: api_headers
      assert_equal [], response.parsed_body["paper_signatures"]
    end
  end

  test "a submitted scan shows as submitted without approved_at and the contract is still pending" do
    with_scan_allowed do
      bundle = create_bundle_via_api(contracts: [ scan_contract_payload("a.pdf") ], recipients: [ { email: "signer@example.com" } ])
      contract = bundle.contracts.sole
      paper_signature_for(contract, bundle.recipients.sole)

      get api_v1_contract_path(contract), headers: api_headers
      assert_response :success
      assert_not response.parsed_body.key?("signed_document")
      item = response.parsed_body["paper_signatures"].sole
      assert_equal "submitted", item["status"]
      assert_nil item["approved_at"]
      assert item["submitted_at"].present?

      get status_api_v1_contract_path(contract), headers: api_headers
      assert_response :ok
    end
  end

  test "the status of a contract signed only on paper redirects to details that do not fail" do
    with_scan_allowed do
      bundle = create_bundle_via_api(contracts: [ scan_contract_payload("a.pdf") ], recipients: [ { email: "signer@example.com" } ])
      contract = bundle.contracts.sole
      paper_signature_for(contract, bundle.recipients.sole, approve: true)

      get status_api_v1_contract_path(contract), headers: api_headers
      assert_redirected_to api_v1_contract_path(contract)
      get api_v1_contract_path(contract), headers: api_headers
      assert_response :success
      assert_nil response.parsed_body["signed_document"]
      assert_equal 1, response.parsed_body["paper_signatures"].size

      get signed_document_api_v1_contract_path(contract), headers: api_headers
      assert_response :not_found
    end
  end

  test "paper_signatures is empty for a contract signed electronically" do
    bundle = create_bundle_via_api(contracts: [ pdf_contract_payload("a.pdf") ], recipients: [ { email: "signer@example.com" } ])
    contract = bundle.contracts.sole
    get api_v1_contract_path(contract), headers: api_headers
    assert_equal [], response.parsed_body["paper_signatures"]

    sign_with_autogram(contract, recipient: bundle.recipients.sole)
    get api_v1_contract_path(contract), headers: api_headers
    assert_equal [], response.parsed_body["paper_signatures"]
    assert response.parsed_body["signed_document"].present?
  end

  test "a contract signed electronically and on paper has both" do
    with_scan_allowed do
      bundle = create_bundle_via_api(
        contracts: [ scan_contract_payload("a.pdf") ],
        recipients: [ { email: "first@example.com" }, { email: "second@example.com" } ]
      )
      contract = bundle.contracts.sole
      first, second = bundle.recipients.order(:id).to_a
      sign_with_autogram(contract, recipient: first)
      paper_signature_for(contract, second, approve: true)

      get api_v1_bundle_path(bundle), headers: api_headers
      assert_response :success
      contract_json = response.parsed_body["contracts"].sole
      assert contract_json["signed_document"].present?
      assert_equal [ second.uuid ], contract_json["paper_signatures"].map { |item| item["recipient"] }
    end
  end

  private

  def create_bundle_via_api(contracts:, recipients:)
    post api_v1_bundles_path, params: { id: SecureRandom.uuid, contracts: contracts, recipients: recipients }, headers: api_headers, as: :json
    assert_response :created, -> { response.body }

    bundle = Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
    assert_equal @organization, bundle.tenant
    bundle
  end

  def pdf_contract_payload(filename)
    {
      id: SecureRandom.uuid,
      allowedMethods: [ "qes" ],
      documents: [ { filename: filename, content: Base64.strict_encode64("%PDF-1.4 #{filename}"), contentType: "application/pdf;base64" } ],
      signatureParameters: { level: "BASELINE_B", format: "PAdES" }
    }
  end

  def text_document(filename, content)
    { filename: filename, content: Base64.strict_encode64(content), contentType: "text/plain;base64" }
  end

  def scan_contract_payload(filename)
    pdf_contract_payload(filename).merge(allowedMethods: [ "qes", "scan" ])
  end

  def with_scan_allowed
    original = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, %w[qes standalone_qes ades scan])
    yield
  ensure
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, original)
  end

  # A paper signature of the recipient as the web flow builds it; submitted, and approved by the owner on request.
  def paper_signature_for(contract, recipient, approve: false)
    signer_contract = recipient.recipient_signer.signer_contracts.find_or_create_by!(contract: contract)
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg") ])
    assert paper.submit!
    paper.approve!(@owner) if approve
    paper.reload
  end

  def api_headers(tenant: @organization, key: @api_key)
    token = JWT.encode({ sub: tenant.id.to_s, exp: 10.minutes.from_now.to_i, jti: SecureRandom.hex(16) }, key, "RS256")
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end
