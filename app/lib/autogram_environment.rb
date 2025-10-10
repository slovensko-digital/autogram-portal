module AutogramEnvironment
  def self.autogram_service
    @@autogram_service ||= AutogramService.new
  end

  def self.avm_service
    @@avm_service ||= AvmService.new
  end
end
