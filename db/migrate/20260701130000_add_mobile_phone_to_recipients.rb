class AddMobilePhoneToRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipients, :mobile_phone, :string
  end
end
