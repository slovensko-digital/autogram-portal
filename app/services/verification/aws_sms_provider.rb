module Verification
  class AwsSmsProvider
    DEFAULT_ORIGINATION_IDENTITY = "OPS".freeze

    def initialize(
      client: Aws::PinpointSMSVoiceV2::Client.new,
      origination_identity: ENV.fetch("AWS_PINPOINT_ORIGINATION_IDENTITY", DEFAULT_ORIGINATION_IDENTITY),
      protect_configuration_id: ENV["AWS_PINPOINT_PROTECT_CONFIGURATION_ID"],
      app_host: ENV["APP_HOST"]
    )
      @client = client
      @origination_identity = origination_identity
      @protect_configuration_id = protect_configuration_id
      @app_host = app_host
    end

    def deliver_code(phone_number:, code:, locale: I18n.default_locale, context: {})
      response = @client.send_text_message(request_payload(phone_number: phone_number, code: code, locale: locale))

      response.respond_to?(:message_id) && response.message_id.present? ? response.message_id : "sms-#{SecureRandom.hex(8)}"
    rescue StandardError => error
      Rails.logger.error("AwsSmsProvider delivery failed for #{phone_number}: #{error.class}: #{error.message} (#{context.inspect})")
      raise
    end

    private

    def request_payload(phone_number:, code:, locale:)
      payload = {
        destination_phone_number: phone_number,
        origination_identity: @origination_identity,
        message_body: message_body(code: code, locale: locale),
        message_type: "TRANSACTIONAL"
      }

      payload[:protect_configuration_id] = @protect_configuration_id if @protect_configuration_id.present?
      payload
    end

    def message_body(code:, locale:)
      base_message = I18n.with_locale(locale) do
        I18n.t("verification.sms.message", code: code)
      end

      return base_message if @app_host.blank?

      "#{base_message}\n\n@#{@app_host} ##{code}"
    end
  end
end
