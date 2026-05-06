module PolicyVersions
  TERMS   = ENV.fetch("TERMS_VERSION",   "1").freeze
  PRIVACY = ENV.fetch("PRIVACY_VERSION", "1").freeze

  def self.current
    { "terms" => TERMS, "privacy" => PRIVACY }
  end
end
