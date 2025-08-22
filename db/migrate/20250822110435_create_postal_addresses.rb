class CreatePostalAddresses < ActiveRecord::Migration[8.0]
  def change
    create_table :postal_addresses do |t|
      t.text :address
      t.string :recipient_name
      t.references :bundle, null: false, foreign_key: true

      t.timestamps
    end
  end
end
