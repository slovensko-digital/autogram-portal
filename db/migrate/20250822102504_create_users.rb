class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email
      t.string :api_token_public_key

      t.timestamps
    end
  end
end
