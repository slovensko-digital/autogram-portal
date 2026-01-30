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
#  contract_id        :bigint           not null
#  recipient_id       :bigint
#  user_id            :bigint
#
# Indexes
#
#  index_sessions_on_contract_id   (contract_id)
#  index_sessions_on_recipient_id  (recipient_id)
#  index_sessions_on_type          (type)
#  index_sessions_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (recipient_id => recipients.id)
#  fk_rails_...  (user_id => users.id)
#
class AvmSession < Session
  # TODO encrypt sensitive fields

  store_accessor :options, :encryption_key, :document_identifier

  validates :document_identifier, :encryption_key, presence: true

  def self.model_name
    Session.model_name
  end

  def avm_url
    base_url = ENV.fetch("AVM_URL", "https://autogram.slovensko.digital").chomp("/")
    "#{base_url}/api/v1/qr-code?guid=#{document_identifier}&key=#{encryption_key}"
  end

  def expired?
    return false unless signing_started_at
    Time.current > signing_started_at + 10.minutes # 10 minute timeout
  end

  def mark_failed!(message = nil)
    super(message)
  end

  def process_webhook(_)
    Avm::DownloadSignedFileJob.perform_later(self)
  end
end
