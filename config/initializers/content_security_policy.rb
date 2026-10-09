# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data, :blob
    policy.worker_src  :self, :blob, :data
    # Allow object/embed tags for PDF previews
    policy.object_src  :self
    # Allow unsafe-eval for Alpine.js and unsafe-inline for inline scripts/event handlers
    policy.script_src  :self, :https, :unsafe_eval, :unsafe_inline
    policy.style_src   :self, :https, :unsafe_inline
    # Allow connections to Autogram desktop app running on client machines
    policy.connect_src :self, :https, "http://localhost:37200", "https://loopback.autogram.slovensko.digital"

    allowed_origins = [ :self ]
    # Allow framing from specific origins; embeddable signing pages add any HTTPS origin (ApplicationController#allow_iframe)
    app_host = ENV["APP_HOST"]
    # Integrators test embedding from localhost on staging; the SDK system tests embed from localhost too
    allowed_origins << "http://localhost:*" unless Rails.env.production?
    allowed_origins << "https://#{app_host}" if app_host.present?
    allowed_origins << "http://#{app_host}" if app_host.present? && Rails.env.development?
    policy.frame_ancestors(*allowed_origins)
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  # Only use nonce for script-src since we're using unsafe-inline for styles
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report violations without enforcing the policy in development.
  config.content_security_policy_report_only = true if Rails.env.development?
end
