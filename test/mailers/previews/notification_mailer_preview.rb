# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  def contract_signed
    contract = Contract.where.not(user: nil).first
    user = contract.user
    NotificationMailer.with(user: user).contract_signed(contract)
  end
end
