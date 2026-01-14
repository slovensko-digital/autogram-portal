class DeviseMailer < Devise::Passwordless::Mailer
  layout "mailer"
  default from: ENV.fetch("MAIL_FROM", "noreply@example.com")
end
