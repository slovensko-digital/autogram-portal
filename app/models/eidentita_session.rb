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
class EidentitaSession < Session
  def self.model_name
    Session.model_name
  end

  def eidentita_url
    url_options = Rails.application.config.action_controller.default_url_options || {}
    link_url = Rails.application.routes.url_helpers.parameters_contract_session_url(contract, self, **url_options)
    "sk.minv.sca://sign?qr=true&linkUrl=#{CGI.escape(link_url)}.json"
  end

  def eidentita_url_mobile
    url_options = Rails.application.config.action_controller.default_url_options || {}
    link_url = Rails.application.routes.url_helpers.parameters_contract_session_url(contract, self, **url_options)
    "sk.minv.sca://sign?qr=false&linkUrl=#{CGI.escape(link_url)}.json"
  end
end
