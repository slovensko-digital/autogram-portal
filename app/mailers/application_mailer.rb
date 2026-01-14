class ApplicationMailer < ActionMailer::Base
  default from: email_address_with_name(ENV.fetch("MAIL_FROM", "noreply@example.com"), "Autogram Portal")

  layout "mailer"
end
