# Plan limits of a tenant (see PlanLimits) and its usage against them.
#
# Limits:
# - :stored_documents   – contracts (documents) the tenant keeps at once
# - :storage            – bytes of all document files and signed versions
# - :signature_requests – documents sent for signature in the current calendar month
# - :timestamps         – timestamps added in the current calendar month
#
# Monthly usage is kept in usage_records, so deleting a bundle does not give the quota back.
module Tenant::Usage
  extend ActiveSupport::Concern

  LIMITS = %i[stored_documents storage signature_requests timestamps].freeze
  MONTHLY_LIMIT_KINDS = { signature_requests: :signature_request, timestamps: :timestamp }.freeze

  UsageEntry = Data.define(:limit, :used, :max) do
    def unlimited?
      max.nil?
    end

    def reached?
      !unlimited? && used >= max
    end

    def percentage
      return if unlimited? || max.zero?

      [ (used * 100.0 / max).round, 100 ].min
    end
  end

  included do
    has_many :usage_records, dependent: :delete_all
  end

  # Usage against every limit in the current calendar month.
  def usage_summary
    LIMITS.map { |limit| UsageEntry.new(limit: limit, used: usage_of(limit), max: limit_of(limit)) }
  end

  def limits
    PlanLimits.for(plan)
  end

  # nil means unlimited.
  def limit_of(limit)
    case limit
    when :stored_documents then limits.max_stored_documents
    when :storage then limits.storage_bytes
    when :signature_requests then limits.monthly_signature_requests
    when :timestamps then limits.monthly_timestamps
    else raise ArgumentError, "Unknown limit #{limit.inspect}"
    end
  end

  def usage_of(limit, period: Time.current.all_month)
    case limit
    when :stored_documents then contracts.count
    when :storage then storage_bytes
    when *MONTHLY_LIMIT_KINDS.keys then monthly_usage(MONTHLY_LIMIT_KINDS.fetch(limit), period: period)
    else raise ArgumentError, "Unknown limit #{limit.inspect}"
    end
  end

  # nil means unlimited.
  def remaining(limit)
    max = limit_of(limit)
    return if max.nil?

    [ max - usage_of(limit), 0 ].max
  end

  def within_limit?(limit, amount = 1)
    max = limit_of(limit)
    max.nil? || usage_of(limit) + amount <= max
  end

  def ensure_within_limit!(limit, amount = 1)
    max = limit_of(limit)
    return if max.nil?

    used = usage_of(limit)
    raise PlanLimits::Exceeded.new(limit: limit, max: max, used: used) if used + amount > max
  end

  def monthly_usage(kind, period: Time.current.all_month)
    usage_records.where(kind: kind).in_period(period).sum(:quantity)
  end

  def storage_bytes
    contract_ids = contracts.select(:id)
    attachments = ActiveStorage::Attachment
      .where(record_type: "Document", name: "blob", record_id: Document.where(contract_id: contract_ids).select(:id))
      .or(ActiveStorage::Attachment.where(record_type: "ContractContentVersion", name: "file", record_id: ContractContentVersion.where(contract_id: contract_ids).select(:id)))

    ActiveStorage::Blob.where(id: attachments.select(:blob_id)).sum(:byte_size)
  end

  def signature_request_allowed?
    within_limit?(:signature_requests)
  end

  def signature_extension_allowed?
    within_limit?(:timestamps)
  end

  def signature_requests_counted?(contracts)
    ids = Array(contracts).map(&:id)
    UsageRecord.signature_request.where(contract_id: ids).distinct.count(:contract_id) == ids.uniq.size
  end

  # Counts the documents sent for signature that have not been counted yet. Raises
  # PlanLimits::Exceeded without recording anything when they do not fit the monthly limit,
  # unless +enforce+ is false (the documents were already signed, so they are counted anyway).
  def record_signature_requests!(contracts, source:, enforce: true)
    with_lock do
      contracts = Array(contracts)
      counted_ids = UsageRecord.signature_request.where(contract_id: contracts.map(&:id)).pluck(:contract_id)
      pending = contracts.uniq(&:id).reject { |contract| counted_ids.include?(contract.id) }
      next 0 if pending.empty?

      ensure_within_limit!(:signature_requests, pending.size) if enforce
      pending.each { |contract| usage_records.create!(kind: :signature_request, source: source, contract: contract) }
      pending.size
    end
  end

  def record_timestamps!(contract, source:, quantity: 1, enforce: true)
    with_lock do
      ensure_within_limit!(:timestamps, quantity) if enforce
      usage_records.create!(kind: :timestamp, source: source, contract: contract, quantity: quantity)
    end
  end
end
