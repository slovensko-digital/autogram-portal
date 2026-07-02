module Verification
  class NullSmsProvider
    attr_reader :last_delivery

    def deliver_code(phone_number:, code:, locale: I18n.default_locale, context: {})
      request_id = "sms-#{SecureRandom.hex(8)}"
      @last_delivery = {
        phone_number: phone_number,
        code: code,
        locale: locale,
        context: context,
        request_id: request_id
      }

      Rails.logger.info("NullSmsProvider delivery #{request_id} to #{phone_number} for #{context.inspect}")

      request_id
    end
  end
end
