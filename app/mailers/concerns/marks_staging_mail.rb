# Marks the subject of every mail sent by a test instance (see StagingInstance);
# the mailer layouts add the notice to the body.
module MarksStagingMail
  extend ActiveSupport::Concern

  included do
    after_action :mark_staging_subject
  end

  private

  def mark_staging_subject
    return unless StagingInstance.active? && message.subject.present?

    message.subject = "[TEST] #{message.subject}"
  end
end
