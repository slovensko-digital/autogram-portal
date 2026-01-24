# == Schema Information
#
# Table name: recipients
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  locale     :string           default("sk"), not null
#  name       :string
#  status     :integer          default("pending"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bundle_id  :bigint           not null
#  user_id    :bigint
#
# Indexes
#
#  index_recipients_on_bundle_id            (bundle_id)
#  index_recipients_on_bundle_id_and_email  (bundle_id,email) UNIQUE
#  index_recipients_on_email                (email)
#  index_recipients_on_status               (status)
#  index_recipients_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
class Recipient < ApplicationRecord
  belongs_to :bundle
  belongs_to :user, optional: true

  enum :status, { pending: 0, notified: 1, signed: 2, declined: 3, sending: 4 }

  validates :email, presence: true, uniqueness: { scope: :bundle_id }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true

  before_create :link_user_by_email
  before_create :check_blocks
  before_create :set_default_locale

  def display_name
    name.presence || user&.display_name || email
  end

  def notify!
    return unless pending?
    update(status: :sending)
    Notification::RecipientBundleCreatedJob.perform_later(self)
  end

  def removable?
    pending? || declined?
  end

  private

  def link_user_by_email
    self.user = User.find_by(email: email)
  end

  def check_blocks
    if RecipientBlock.blocked?(email)
      errors.add(:email, "is blocked")
      throw :abort
    end
  end

  def set_default_locale
    self.locale ||= user&.locale || I18n.default_locale.to_s
  end
end
