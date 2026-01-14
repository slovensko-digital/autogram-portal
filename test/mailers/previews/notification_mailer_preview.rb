# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  def contract_signed
    contract = Contract.where.not(user: nil).first
    user = contract.user
    NotificationMailer.with(user: user).contract_signed(contract)
  end

  def bundle_completed
    bundle = Bundle.first
    user = bundle.author
    NotificationMailer.with(user: user).bundle_completed(bundle)
  end

  def bundle_created
    bundle = Bundle.joins(:recipients).where.not(users: { id: nil }).first
    user = bundle.recipients.first
    NotificationMailer.with(user: user).bundle_created(bundle)
  end
end
