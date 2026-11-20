# == Schema Information
#
# Table name: activity_events
#
#  id              :bigint           not null, primary key
#  byte_size       :bigint
#  channel         :string
#  documents_count :integer
#  kind            :string           not null
#  plan            :string           not null
#  signing_method  :string
#  created_at      :datetime         not null
#  tenant_id       :bigint
#
# Indexes
#
#  index_activity_events_on_kind_and_created_at  (kind,created_at)
#  index_activity_events_on_tenant_id            (tenant_id)
#

# Anonymous record of a document uploaded or signed, for usage statistics in BI tools such as Metabase.
# Retention deletes the documents themselves (see PlanLimits), so events reference no document and hold
# no personal data. The tenant id is kept without a foreign key.
#
# - plan:    the tenant's plan at the time, "anonymous" without a tenant
# - channel: "web" or "api" for uploads, "web" or "embedded" (SDK iframe) for signatures; nil for events
#            backfilled when the table was created
class ActivityEvent < ApplicationRecord
  ANONYMOUS_PLAN = "anonymous".freeze

  enum :kind, { document_uploaded: "document_uploaded", document_signed: "document_signed" }, validate: true

  validates :plan, presence: true

  def self.record_upload!(contract)
    create!(
      kind: :document_uploaded,
      channel: Current.channel || "web",
      documents_count: contract.documents.size,
      byte_size: contract.documents.sum { it.blob.byte_size },
      **tenant_attributes(contract.tenant)
    )
  end

  def self.record_signature!(session)
    create!(
      kind: :document_signed,
      channel: session.iframe_param.present? ? "embedded" : "web",
      signing_method: signing_method_for(session),
      **tenant_attributes(session.contract.tenant)
    )
  end

  # AutogramSession -> autogram, AdesEvidenceSession -> ades_evidence
  def self.signing_method_for(session)
    session.type.delete_suffix("Session").underscore
  end

  def self.tenant_attributes(tenant)
    { tenant_id: tenant&.id, plan: tenant&.plan || ANONYMOUS_PLAN }
  end
  private_class_method :tenant_attributes
end
