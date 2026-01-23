# == Schema Information
#
# Table name: autogram_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  signing_started_at :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class AutogramSession < ApplicationRecord
  has_one :session, as: :sessionable, dependent: :destroy

  delegate :contract, :status, :status=, to: :session

  validates :signing_started_at, presence: true

  def mark_completed!
    session.update!(status: :completed)
    update!(completed_at: Time.current)
  end
end
