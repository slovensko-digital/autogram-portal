require "test_helper"
require_relative "../../support/plan_limits_helper"

class Tenant::UsageTest < ActiveSupport::TestCase
  include PlanLimitsHelper

  setup do
    @tenant = Tenant.create!(name: "Limitovaná firma")
  end

  test "counts stored documents and their storage including signed versions" do
    contract = create_contract(@tenant, bytes: 100)
    create_contract(@tenant, bytes: 50)
    create_contract(Tenant.create!(name: "Iná firma"), bytes: 1_000)
    contract.add_signed_content_version!(content: "signed" * 10, filename: "signed.pdf", content_type: "application/pdf", origin: "signing")

    assert_equal 2, @tenant.usage_of(:stored_documents)
    assert_equal contract.documents.sole.blob.byte_size + 50 + "%PDF-1.4 ".bytesize + 60, @tenant.usage_of(:storage)
  end

  test "monthly usage counts only the current month" do
    contract = create_contract(@tenant)
    @tenant.usage_records.create!(kind: :timestamp, source: :extension, contract: contract, created_at: 1.month.ago)
    @tenant.record_timestamps!(contract, source: :extension, quantity: 2)

    assert_equal 2, @tenant.usage_of(:timestamps)
    assert_equal 1, @tenant.usage_of(:timestamps, period: 1.month.ago.all_month)
  end

  test "a document sent for signature is counted once and deleting it does not return the quota" do
    with_plan_limits("BASIC_MONTHLY_SIGNATURE_REQUESTS" => "2") do
      first = create_contract(@tenant)
      second = create_contract(@tenant)

      assert_equal 2, @tenant.record_signature_requests!([ first, second ], source: :notification)
      assert_equal 0, @tenant.record_signature_requests!([ first ], source: :recipient_signature)
      assert_equal 0, @tenant.remaining(:signature_requests)
      assert_not @tenant.signature_request_allowed?

      first.destroy!
      assert_equal 2, @tenant.usage_of(:signature_requests)
      assert_nil @tenant.usage_records.signature_request.order(:id).first.contract_id
    end
  end

  test "documents beyond the monthly limit are not recorded unless they were already signed" do
    with_plan_limits("BASIC_MONTHLY_SIGNATURE_REQUESTS" => "1") do
      contracts = [ create_contract(@tenant), create_contract(@tenant) ]

      error = assert_raises(PlanLimits::Exceeded) { @tenant.record_signature_requests!(contracts, source: :notification) }
      assert_equal :signature_requests, error.limit
      assert_equal 1, error.max
      assert_equal 0, @tenant.usage_records.count

      @tenant.record_signature_requests!(contracts, source: :recipient_signature, enforce: false)
      assert_equal 2, @tenant.usage_of(:signature_requests)
    end
  end

  test "timestamps stop at the monthly limit" do
    with_plan_limits("BASIC_MONTHLY_TIMESTAMPS" => "1") do
      contract = create_contract(@tenant)
      @tenant.record_timestamps!(contract, source: :extension)

      assert_not @tenant.signature_extension_allowed?
      assert_raises(PlanLimits::Exceeded) { @tenant.record_timestamps!(contract, source: :extension) }
      assert_equal 1, @tenant.usage_of(:timestamps)
    end
  end

  test "unlimited plans record usage for billing without limiting it" do
    @tenant.update!(plan: :pro)

    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => nil, "PRO_MONTHLY_TIMESTAMPS" => nil) do
      contract = create_contract(@tenant)
      3.times { @tenant.record_timestamps!(contract, source: :archivation) }

      assert_nil @tenant.remaining(:timestamps)
      assert @tenant.within_limit?(:timestamps, 1_000)
      assert_equal 3, @tenant.usage_of(:timestamps)
    end
  end

  test "usage summary lists every limit" do
    with_plan_limits("BASIC_MAX_STORED_DOCUMENTS" => "2", "BASIC_STORAGE_GB" => nil, "BASIC_MONTHLY_SIGNATURE_REQUESTS" => nil, "BASIC_MONTHLY_TIMESTAMPS" => nil) do
      create_contract(@tenant)
      create_contract(@tenant)

      summary = @tenant.usage_summary.index_by(&:limit)
      assert_equal Tenant::Usage::LIMITS, summary.keys
      assert summary[:stored_documents].reached?
      assert_equal 100, summary[:stored_documents].percentage
      assert summary[:storage].unlimited?
      assert_nil summary[:storage].percentage
    end
  end

  test "changing the plan remembers when it changed" do
    assert_nil @tenant.plan_changed_at

    @tenant.update!(name: "Premenovaná")
    assert_nil @tenant.plan_changed_at

    @tenant.update!(plan: :pro)
    assert_in_delta Time.current, @tenant.plan_changed_at, 5.seconds
  end

  private

  def create_contract(tenant, bytes: 10)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 #{'a' * bytes}"), filename: "doc.pdf", content_type: "application/pdf")
    Contract.create!(tenant: tenant, documents: [ Document.new(blob: blob) ])
  end
end
