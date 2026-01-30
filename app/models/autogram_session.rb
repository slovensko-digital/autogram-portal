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
class AutogramSession < Session
  def self.model_name
    Session.model_name
  end
end
