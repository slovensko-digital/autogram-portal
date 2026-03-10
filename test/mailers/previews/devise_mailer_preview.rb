# Preview all emails at http://localhost:3000/rails/mailers/devise_mailer
class DeviseMailerPreview < ActionMailer::Preview
  def magic_link
    user = User.first || User.new(email: "user@example.com")
    token = "sample_magic_link_token_12345"

    DeviseMailer.with(locale: params[:locale]).magic_link(user, token, { remember_me: false })
  end

  def confirmation_instructions
    user = User.first || User.new(email: "user@example.com")
    token = "sample_confirmation_token_12345"

    DeviseMailer.with(locale: params[:locale]).confirmation_instructions(user, token)
  end

  def email_changed
    user = User.first || User.new(email: "user@example.com", unconfirmed_email: nil)

    DeviseMailer.with(locale: params[:locale]).email_changed(user)
  end

  def unlock_instructions
    user = User.first || User.new(email: "user@example.com")
    token = "sample_unlock_token_12345"

    DeviseMailer.with(locale: params[:locale]).unlock_instructions(user, token)
  end
end
