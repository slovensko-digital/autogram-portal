Rails.application.config.footer = {
  support_email: ENV.fetch("FOOTER_EMAIL", "podpora@slovensko.digital"),
  provider_name: ENV.fetch("FOOTER_PROVIDER_NAME", "Slovensko.Digital, s.r.o.")
}
