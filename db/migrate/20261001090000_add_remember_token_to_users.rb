# Users sign in without passwords, so Devise's rememberable cannot derive the
# remember cookie from the password salt and keeps a token of its own instead.
class AddRememberTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :remember_token, :string
  end
end
