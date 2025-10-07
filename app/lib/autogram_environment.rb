module AutogramEnvironment
  AUTOGRAM_BASE_URL = "http://localhost:7200"

  def self.autogram_service
    @@autogram_service ||= AutogramService.new
  end

  def self.avm_service
    @@avm_service ||= AvmService.new
  end
end
