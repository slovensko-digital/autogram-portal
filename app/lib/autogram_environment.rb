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
    @@sms_provider ||= Verification::NullSmsProvider.new
  end

  def self.ades_signing_service
    @@ades_signing_service ||= AdesServerSigningService.new
  end
end
