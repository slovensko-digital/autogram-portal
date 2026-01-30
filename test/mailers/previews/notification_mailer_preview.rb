# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  def contract_signed
    bundle = Bundle.joins(:recipients).where.not(recipients: { id: nil }).first
    contract = bundle.contracts.first
    signer = bundle.recipients.first
    user = bundle.author
    NotificationMailer.with(user: user).contract_signed(contract, signer)
  end

  def bundle_contract_signed
    bundle = Bundle.joins(:recipients).where.not(recipients: { id: nil }).first
    contract = bundle.contracts.first
    signer = bundle.recipients.first
    user = bundle.author
    NotificationMailer.with(user: user).bundle_contract_signed(bundle, contract, signer)
  end

  def bundle_completed
    bundle = Bundle.first
    user = bundle.author
    NotificationMailer.with(user: user).bundle_completed(bundle)
  end

  def signature_requested
    bundle = Bundle.joins(:recipients).where(recipients: { notification_status: "notified" }).first
    user = bundle.recipients.find_by(notification_status: "notified")
    NotificationMailer.with(user: user).signature_requested(bundle)
  end
end
