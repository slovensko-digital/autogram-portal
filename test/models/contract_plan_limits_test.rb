require "test_helper"
require_relative "../support/plan_limits_helper"

# Plan limits enforced on contracts: document size, stored documents, storage and timestamps.
class ContractPlanLimitsTest < ActiveSupport::TestCase
  include PlanLimitsHelper

  setup do
    @tenant = Tenant.create!(name: "Limitovaná firma")
  end

  test "a document may not exceed the size limit, also without a tenant" do
    with_plan_limits("MAX_DOCUMENT_SIZE_MB" => "1") do
      contract = Contract.new(documents: [ Document.new(blob: pdf_blob(bytes: 600.kilobytes)), Document.new(blob: pdf_blob(bytes: 600.kilobytes)) ])

      assert_not contract.valid?
      assert_includes contract.errors[:base], I18n.t("activerecord.errors.models.contract.attributes.base.too_large", max: PlanLimits::Exceeded.format(:document_size, 1.megabyte))

      contract.documents = [ Document.new(blob: pdf_blob(bytes: 600.kilobytes)) ]
      assert contract.valid?, -> { contract.errors.full_messages.to_sentence }
    end
  end

  test "a tenant stores only as many documents as its plan allows" do
    with_plan_limits("BASIC_MAX_STORED_DOCUMENTS" => "1") do
      Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])
      contract = Contract.new(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])

      assert_not contract.save
      assert_includes contract.errors[:base], I18n.t("activerecord.errors.models.contract.attributes.base.stored_documents_limit", max: 1)

      other_tenant = Tenant.create!(name: "Iná firma")
      assert Contract.create!(tenant: other_tenant, documents: [ Document.new(blob: pdf_blob) ])
    end
  end

  test "an anonymous document cannot be claimed by a tenant without room for it" do
    with_plan_limits("BASIC_MAX_STORED_DOCUMENTS" => "1") do
      Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])
      anonymous = Contract.create!(documents: [ Document.new(blob: pdf_blob) ])

      assert_not anonymous.update(tenant: @tenant)
      assert anonymous.reload.anonymous?
    end
  end

  test "updating a stored document does not count it again" do
    with_plan_limits("BASIC_MAX_STORED_DOCUMENTS" => "1") do
      contract = Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])

      assert contract.update(allowed_methods: [ "qes" ]), -> { contract.errors.full_messages.to_sentence }
    end
  end

  test "new files must fit the storage of the tenant" do
    @tenant.update!(plan: :pro)

    with_plan_limits("PRO_STORAGE_GB" => "0") do
      contract = Contract.new(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])

      assert_not contract.save
      assert_includes contract.errors[:base], I18n.t("activerecord.errors.models.contract.attributes.base.storage_limit", max: PlanLimits::Exceeded.format(:storage, 0))
    end
  end

  test "extending signatures counts a timestamp and stops at the monthly limit" do
    with_plan_limits("BASIC_MONTHLY_TIMESTAMPS" => "1") do
      contract = Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])
      contract.define_singleton_method(:extendable_signatures?) { |**| true }

      with_fake_extension do
        assert contract.extend_signatures!(target_level: "T")
        assert_equal 1, @tenant.usage_records.timestamp.source_extension.sum(:quantity)

        assert_raises(PlanLimits::Exceeded) { contract.extend_signatures!(target_level: "T") }
        assert_equal 1, contract.content_versions.where(origin: "extension").count
      end
    end
  end

  test "archivation records its timestamps separately" do
    @tenant.update!(plan: :pro)
    contract = Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])
    contract.define_singleton_method(:extendable_signatures?) { |**| true }

    with_fake_extension do
      contract.extend_signatures!(target_level: "LTA", usage_source: :archivation)
    end

    assert_equal [ "archivation" ], @tenant.usage_records.timestamp.pluck(:source)
  end

  test "AVM is unavailable for timestamped signatures once the tenant has no timestamps left" do
    with_plan_limits("BASIC_MONTHLY_TIMESTAMPS" => "0") do
      contract = Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ])
      contract.signature_parameters.update!(level: "BASELINE_T")
      assert_includes AvmSession.unavailability_reasons(nil, contract), :timestamp_limit_reached

      contract.signature_parameters.update!(level: "BASELINE_B")
      assert_not_includes AvmSession.unavailability_reasons(nil, contract), :timestamp_limit_reached

      anonymous = Contract.create!(documents: [ Document.new(blob: pdf_blob) ])
      anonymous.signature_parameters.update!(level: "BASELINE_T")
      assert_not_includes AvmSession.unavailability_reasons(nil, anonymous), :timestamp_limit_reached
    end
  end

  private

  def pdf_blob(bytes: 10)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 #{'a' * bytes}"), filename: "doc.pdf", content_type: "application/pdf")
  end

  def with_fake_extension
    service = AutogramEnvironment.autogram_service
    service.define_singleton_method(:extend_signatures) { |document, **| "extended:#{document.filename}" }
    yield
  ensure
    service.singleton_class.send(:remove_method, :extend_signatures)
  end
end
