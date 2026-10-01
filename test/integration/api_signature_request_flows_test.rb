require "test_helper"
require "jwt"
require "openssl"
require_relative "../support/signing_flow_helper"

# End-to-end signature requests created through the API by an organization and
# signed by recipients through the web.
class ApiSignatureRequestFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SigningFlowHelper

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

    sign_in colleague
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

  def api_headers(tenant: @organization, key: @api_key)
    token = JWT.encode({ sub: tenant.id.to_s, exp: 10.minutes.from_now.to_i, jti: SecureRandom.hex(16) }, key, "RS256")
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end
