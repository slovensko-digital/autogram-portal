class CreateRecipientBlock < ActiveRecord::Migration[8.1]
  def change
    create_table :recipient_blocks do |t|
      t.string :email, null: false
      t.timestamps
    end

    add_index :recipient_blocks, :email, unique: true
  end
end
