# Preview all emails at http://localhost:3000/rails/mailers/verification_mailer
class VerificationMailerPreview < ActionMailer::Preview
  def otp_code
    code = "123456"
    email = "user@example.com"
    VerificationMailer.with(code: code, email: email, locale: params[:locale]).otp_code
  end
end
