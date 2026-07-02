module AutogramEnvironment
  def self.autogram_service
    @@autogram_service ||= AutogramService.new
  end

  def self.avm_service
    @@avm_service ||= AvmService.new
  end

  def self.eidentita_service
    @@eidentita_service ||= EidentitaService.new
  end

  def self.sms_provider
    return @sms_provider if instance_variable_defined?(:@sms_provider)

    @sms_provider = if aws_sms_configured?
      Verification::AwsSmsProvider.new
    elsif null_sms_provider_allowed?
      Verification::NullSmsProvider.new
    end
  end

  def self.email_otp_provider
    @email_otp_provider ||= Verification::EmailOtpProvider.new
  end

  def self.ades_signing_service
    @@ades_signing_service ||= AdesServerSigningService.new
  end

  def self.reset_verification_providers!
    remove_instance_variable(:@sms_provider) if instance_variable_defined?(:@sms_provider)
    remove_instance_variable(:@email_otp_provider) if instance_variable_defined?(:@email_otp_provider)
  end

  def self.aws_sms_configured?
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_SMS_ENABLED].all? { |key| ENV[key].present? }
  end

  def self.null_sms_provider_allowed?
    ActiveModel::Type::Boolean.new.cast(ENV["ALLOW_NULL_SMS_PROVIDER"]) || !Rails.env.production?
  end
end
