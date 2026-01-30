class AddRecipientToSession < ActiveRecord::Migration[8.1]
  def change
    add_reference :sessions, :recipient, foreign_key: true, type: :bigint
  end
end
