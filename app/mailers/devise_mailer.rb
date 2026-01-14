class DeviseMailer < Devise::Passwordless::Mailer
  layout "mailer"
  default from: ENV.fetch("MAIL_FROM", "noreply@example.com")

  def magic_link(record, token, opts = {})
    set_locale_for_user(record)
    super
  end

  def confirmation_instructions(record, token, opts = {})
    set_locale_for_user(record)
    super
  end

  def email_changed(record, opts = {})
    set_locale_for_user(record)
    super
  end

  def unlock_instructions(record, token, opts = {})
    set_locale_for_user(record)
    super
  end

  private

  def set_locale_for_user(user)
    I18n.locale = user&.locale || I18n.default_locale
  end
end
