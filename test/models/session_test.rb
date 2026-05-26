# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default("pending"), not null
#  type               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  index_sessions_on_signer_contract_id  (signer_contract_id)
#  index_sessions_on_type                (type)
#
# Foreign Keys
#
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "keeps iframe open while public bundle still has unsigned contracts" do
    contract_one = create_contract
    contract_two = create_contract
    Bundle.create!(author: users(:one), contracts: [ contract_one, contract_two ], publicly_visible: true)
    attach_signed_document(contract_one)

    session = create_session_for(contract_one, options: { "iframe" => "true" })

    assert_equal 2, session.bundle_contracts_total
    assert_equal 1, session.remaining_bundle_contracts_count
    assert_not session.bundle_signing_complete?
    assert session.inline_bundle_success?
    assert_not session.close_iframe_after_completion?
    assert_equal false, session.completion_event_payload[:close_iframe]
  end

  test "closes iframe when public single-contract bundle is fully signed" do
    contract = create_contract
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ], publicly_visible: true)
    attach_signed_document(contract)

    session = create_session_for(contract, options: { "iframe" => "true" })

    assert_equal 1, session.bundle_contracts_total
    assert_equal 0, session.remaining_bundle_contracts_count
    assert session.bundle_signing_complete?
    assert_not session.inline_bundle_success?
    assert session.close_iframe_after_completion?
    assert_equal bundle.uuid, session.completion_event_payload[:bundle_id]
    assert_equal true, session.completion_event_payload[:bundle_completed]
  end

  private

  def create_contract
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "session-test.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
  end

  def create_session_for(contract, options: nil)
    signer = AnonymousSigner.create!
    signer_contract = signer.signer_contracts.create!(contract: contract)
    signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current,
      options: options
    )
  end

  def attach_signed_document(contract)
    contract.signed_document.attach(
      io: StringIO.new("signed pdf content"),
      filename: "signed.pdf",
      content_type: "application/pdf"
    )
  end
end
