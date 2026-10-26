# A test instance of the portal (staging), marked by PRODUCTION_URL pointing to the live portal.
# People find staging through search engines and use it as the real portal, so a test instance
# says so on every page (except embedded iframes) and in every email, links to production and
# sends mail meant for people outside an organization to its owners instead (StagingMail), unless
# an administrator gives the organization the staging_real_mail feature. Anyone may sign up,
# unless SIGNUP_ALLOWED_DOMAINS (comma-separated) restricts it; existing users and invited
# recipients keep their access. Every organization there may use the API for free
# (Tenant#api_enabled?).
#
# Values are read on every call, so tests can change ENV without resetting anything.
module StagingInstance
  def self.active?
    production_url.present?
  end

  def self.production_url
    ENV["PRODUCTION_URL"].presence
  end

  def self.production_host
    URI(production_url).host if active?
  end

  def self.production_url_for(path)
    URI.join(production_url, path).to_s if active?
  end

  # Whether mail concerning the tenant reaches only its members (StagingMail).
  def self.redirect_mail_for?(tenant)
    active? && !tenant&.feature_enabled?(:staging_real_mail)
  end

  def self.signup_allowed_domains
    ENV["SIGNUP_ALLOWED_DOMAINS"].to_s.split(",").map { it.strip.downcase }.compact_blank
  end

  def self.signup_restricted?
    active? && signup_allowed_domains.any?
  end

  # "@slovensko.digital, @example.com" for messages.
  def self.signup_allowed_addresses
    signup_allowed_domains.map { "@#{it}" }.join(", ")
  end

  # Subdomains of an allowed domain are allowed too.
  def self.signup_allowed?(email)
    return true unless signup_restricted?

    domain = email.to_s.strip.downcase.split("@", 2).second.to_s
    domain.present? && signup_allowed_domains.any? { domain == it || domain.end_with?(".#{it}") }
  end
end
