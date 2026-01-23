# == Schema Information
#
# Table name: sessions
#
#  id               :bigint           not null, primary key
#  sessionable_type :string           not null
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  contract_id      :bigint           not null
#  sessionable_id   :bigint           not null
#  user_id          :bigint
#
# Indexes
#
#  index_sessions_on_contract_and_sessionable  (contract_id,sessionable_type,sessionable_id)
#  index_sessions_on_contract_id               (contract_id)
#  index_sessions_on_sessionable               (sessionable_type,sessionable_id)
#  index_sessions_on_user_id                   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (user_id => users.id)
#
class Session < ApplicationRecord
  belongs_to :contract
  belongs_to :sessionable, polymorphic: true
  belongs_to :user, optional: true

  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2,
    expired: 3
  }

  delegate :signing_started_at, :completed_at, :error_message, to: :sessionable

  scope :active, -> { where(status: :pending) }
  scope :recent, -> { order(created_at: :desc) }

  def eidentita?
    sessionable_type == "EidentitaSession"
  end

  def avm?
    sessionable_type == "AvmSession"
  end

  def autogram?
    sessionable_type == "AutogramSession"
  end

  def sync_status!
    update!(status: sessionable.status)
  end
end
