class AddRecipients < ActiveRecord::Migration[8.1]
  def change
     create_table :recipients do |t|
      t.references :bundle, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :email, null: false
      t.string :name, null: true
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    add_index :recipients, [ :bundle_id, :email ], unique: true
    add_index :recipients, :email
    add_index :recipients, :status
  end
end
