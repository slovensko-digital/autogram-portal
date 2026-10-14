class ApplicationMailer < ActionMailer::Base
  include MarksStagingMail

  default from: ENV.fetch("MAIL_FROM", "noreply@example.com")

  layout "mailer"
end
