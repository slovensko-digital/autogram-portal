module Verification
  class EmailOtpProvider
    def deliver_code(email:, code:, locale: I18n.default_locale, context: {})
      request_id = "email-#{SecureRandom.hex(8)}"

      VerificationMailer.with(
        email: email,
        code: code,
        locale: locale,
        request_id: request_id,
        context: context
      ).otp_code.deliver_now

      request_id
    end
  end
end
