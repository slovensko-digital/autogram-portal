# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data, :blob
    # Allow object/embed tags for PDF previews
    policy.object_src  :self
    # Allow unsafe-eval for Alpine.js and unsafe-inline for inline scripts/event handlers
    policy.script_src  :self, :https, :unsafe_eval, :unsafe_inline
    policy.style_src   :self, :https, :unsafe_inline
    # Allow connections to Autogram desktop app running on client machines
    policy.connect_src :self, :https, "http://localhost:37200", "https://loopback.autogram.slovensko.digital"

    # Allow framing from specific origins
    app_host = ENV["APP_HOST"]
    if Rails.env.production? && app_host.present?
      policy.frame_ancestors "https://#{app_host}"
    elsif Rails.env.development?
      allowed_origins = [ :self, "http://localhost:*" ]
      allowed_origins << "https://#{app_host}" if app_host.present?
      policy.frame_ancestors(*allowed_origins)
    end
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  # Only use nonce for script-src since we're using unsafe-inline for styles
  config.content_security_policy_nonce_directives = %w(script-src)

  # Report violations without enforcing the policy in development.
  config.content_security_policy_report_only = true if Rails.env.development?
end
