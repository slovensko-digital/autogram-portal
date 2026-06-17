class MakeEmailNullableInRecipients < ActiveRecord::Migration[8.0]
  def change
    change_column_null :recipients, :email, true
  end
end
