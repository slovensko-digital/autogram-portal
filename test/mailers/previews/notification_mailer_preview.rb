# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  def contract_signed
    contract = Contract.where.not(user: nil).first
    user = contract.user
    NotificationMailer.contract_signed(contract, user)
  end
end
