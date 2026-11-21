class ApplicationMailer < ActionMailer::Base
  include StagingMail

  default from: ENV.fetch("MAIL_FROM", "noreply@example.com")

  layout "mailer"
end
