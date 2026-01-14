class NotificationMailer < ApplicationMailer
  def contract_signed(contract, user)
    @contract = contract
    @user = user
    mail(to: @user.email, subject: 'Your contract has been signed')
  end
end
