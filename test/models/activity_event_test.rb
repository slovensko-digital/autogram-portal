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
require "test_helper"

class ActivityEventTest < ActiveSupport::TestCase
  test "uploading a document records its files and the plan of the tenant" do
    contract = create_contract(tenant: tenants(:one), content: "%PDF-1.4 #{'a' * 100}")

    event = ActivityEvent.document_uploaded.sole
    assert_equal "basic", event.plan
    assert_equal tenants(:one).id, event.tenant_id
    assert_equal "web", event.channel
    assert_equal 1, event.documents_count
    assert_equal contract.documents.sole.blob.byte_size, event.byte_size
  end

  test "an anonymous upload is recorded without a tenant" do
    create_contract

    event = ActivityEvent.document_uploaded.sole
    assert_equal ActivityEvent::ANONYMOUS_PLAN, event.plan
    assert_nil event.tenant_id
  end

  test "signing records the signing method and whether the page was embedded" do
    tenants(:one).update!(plan: :pro)
    contract = create_contract(tenant: tenants(:one))

    create_session_for(contract, options: { "iframe" => "true" }).signed!

    event = ActivityEvent.document_signed.sole
    assert_equal "autogram", event.signing_method
    assert_equal "embedded", event.channel
    assert_equal "pro", event.plan
    assert_equal tenants(:one).id, event.tenant_id
  end

  test "a session that does not end signed records no signature" do
    create_session_for(create_contract).failed!

    assert_not ActivityEvent.document_signed.exists?
  end

  test "events outlive the deleted document" do
    contract = create_contract
    create_session_for(contract).signed!

    contract.destroy!

    assert_equal %w[document_signed document_uploaded], ActivityEvent.order(:kind).pluck(:kind)
  end

  test "the signing method is the session type without its suffix" do
    assert_equal "ades_evidence", ActivityEvent.signing_method_for(AdesEvidenceSession.new)
    assert_equal "eidentita", ActivityEvent.signing_method_for(EidentitaSession.new)
  end

  private

  def create_contract(tenant: nil, content: "%PDF-1.4 activity")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: "activity.pdf", content_type: "application/pdf")
    Contract.create!(tenant: tenant, documents_attributes: [ { blob: blob } ])
  end

  def create_session_for(contract, options: nil)
    signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: contract)
    signer_contract.sessions.create!(type: "AutogramSession", signing_started_at: Time.current, options: options)
  end
end
