require "test_helper"
require_relative "../support/signing_flow_helper"
require_relative "../support/plan_limits_helper"

class AwaitingBatchSigningTest < ActiveSupport::TestCase
  include SigningFlowHelper
  include PlanLimitsHelper

  setup do
    @signer = confirmed_user("signer@example.com")
    @first_tenant = Tenant.create!(name: "Firma A", plan: :pro)
    @second_tenant = Tenant.create!(name: "Firma B", plan: :pro)
  end

  test "collects the documents awaiting the user across bundles of different organizations, oldest bundle first" do
    newer = create_bundle(@second_tenant, [ "druha.pdf" ], created_at: 1.day.ago)
    older = create_bundle(@first_tenant, [ "prva.pdf", "tretia.pdf" ], created_at: 2.days.ago)

    batch = batch_for(@signer)

    assert batch.available?
    assert_equal [ "prva.pdf", "tretia.pdf", "druha.pdf" ], batch.items.map { |item| item.contract.display_name.to_s }
    assert_equal [ older, older, newer ], batch.items.map(&:bundle)
    assert_empty batch.other_items
  end

  test "leaves out what the user cannot sign now" do
    signed = create_bundle(@first_tenant, [ "podpisana.pdf" ])
    signed.recipients.sole.signer_contracts.sole.update!(signed_at: Time.current)
    declined = create_bundle(@first_tenant, [ "odmietnuta.pdf" ])
    declined.recipients.sole.signer_contracts.sole.update!(declined_at: Time.current)
    withdrawn = create_bundle(@first_tenant, [ "stiahnuta.pdf" ])
    withdrawn.recipients.sole.update!(withdrawn_at: Time.current)
    create_bundle(@second_tenant, [ "ina.pdf" ], email: "someone-else@example.com")
    create_bundle(@second_tenant, [ "moja.pdf" ])

    batch = batch_for(@signer)

    assert_equal [ "moja.pdf" ], batch.items.map { |item| item.contract.display_name.to_s }
    assert_not batch.available?, "one document is not worth a batch"
  end

  test "documents Autogram cannot sign in a batch are left for signing one by one" do
    create_bundle(@first_tenant, [ "prva.pdf", "druha.pdf" ])
    ades_only = create_bundle(@second_tenant, [ "ades.pdf" ])
    ades_only.contracts.sole.update!(allowed_methods: [ "ades" ])
    several_files = create_bundle(@second_tenant, [ "kontajner.pdf" ])
    several_files.contracts.sole.documents.create!(blob: pdf_blob("priloha.pdf"))

    batch = batch_for(@signer)

    assert_equal [ "prva.pdf", "druha.pdf" ], batch.items.map { |item| item.contract.display_name.to_s }
    assert_equal [ ades_only, several_files ].map(&:id).sort, batch.other_items.map { |item| item.bundle.id }.sort
  end

  test "skips bundles whose sender used up the monthly signature requests" do
    with_plan_limits("BASIC_MONTHLY_SIGNATURE_REQUESTS" => "0") do
      basic = Tenant.create!(name: "Basic firma")
      create_bundle(basic, [ "limit.pdf" ])
      create_bundle(@first_tenant, [ "prva.pdf", "druha.pdf" ])

      assert_equal [ "prva.pdf", "druha.pdf" ], batch_for(@signer).items.map { |item| item.contract.display_name.to_s }
    end
  end

  private

  def batch_for(user)
    AwaitingBatchSigning.new(Bundle.recipient_user(user).distinct.awaiting_signature_of(user), user: user)
  end

  def create_bundle(tenant, filenames, email: @signer.email, created_at: Time.current)
    contracts = filenames.map do |filename|
      Contract.create!(
        tenant: tenant,
        documents: [ Document.new(blob: pdf_blob(filename)) ],
        allowed_methods: [ "qes" ],
        signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
      )
    end
    # The recipient gets a signer contract for every document of the bundle.
    Bundle.create!(tenant: tenant, contracts: contracts, created_at: created_at).tap do |bundle|
      bundle.recipients.create!(email: email)
    end
  end
end
