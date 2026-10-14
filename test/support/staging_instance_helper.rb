# Turns the instance into a test one (see StagingInstance) for each test and restores ENV afterwards.
module StagingInstanceHelper
  PRODUCTION_URL = "https://agp.slovensko.digital".freeze
  STAGING_ENV_KEYS = %w[PRODUCTION_URL SIGNUP_ALLOWED_DOMAINS ALTCHA_HMAC_KEY].freeze

  def self.included(base)
    base.setup do
      @previous_staging_env = STAGING_ENV_KEYS.index_with { ENV[it] }
      ENV["PRODUCTION_URL"] = PRODUCTION_URL
      ENV.delete("SIGNUP_ALLOWED_DOMAINS")
      # The sign-up captcha is verified only when its key is set (as in a local .env).
      ENV.delete("ALTCHA_HMAC_KEY")
    end

    base.teardown do
      @previous_staging_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
