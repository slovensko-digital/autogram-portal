class CreateIdentities < ActiveRecord::Migration[8.0]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true

      t.string :provider, null: false
      t.string :uid, null: false

      t.timestamps
    end

    add_index :identities, [ :provider, :uid ], unique: true
    add_index :identities, [ :user_id, :provider ], unique: true
  end
end
