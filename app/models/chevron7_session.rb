# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default(0), not null
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
class Chevron7Session < Session
  def self.model_name
    Session.model_name
  end

  def self.available?(qscd, contract)
    unavailability_reasons(qscd, contract).empty?
  end

  # Chevron7 signs a single PDF (PAdES, or XAdES in an ASiC-E container) and reads the card itself,
  # so no card choice makes it unavailable. The parameters JSON carries only format, level and
  # container, not the XML data container details other documents need.
  def self.unavailability_reasons(_qscd, contract)
    reasons = []
    reasons << :multiple_files if contract.documents.count > 1
    reasons << :unsupported_document_type unless contract.documents.first&.is_pdf?
    reasons << :prepared_signature_fields if contract.prepared_signature_fields_source_attached?
    reasons
  end

  # Opens Chevron7 on macOS; the app fetches the JSON behind linkUrl with the session token.
  def chevron7_url
    url_options = Rails.application.config.action_controller.default_url_options || {}
    link_url = Rails.application.routes.url_helpers.parameters_contract_session_url(
      contract,
      self,
      format: :json,
      session_token: SessionAccessToken.generate(contract: contract, session: self),
      **url_options
    )
    "chevron7://sign?linkUrl=#{CGI.escape(link_url)}"
  end
end
