class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('MAIL_FROM', 'noreply@example.com')

  layout "mailer"
end
